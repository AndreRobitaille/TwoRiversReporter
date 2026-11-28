module CouncilProfiles
  # The weekly digest contains resident-facing facts only. Import timestamps,
  # attendance, procedural votes and regenerated database IDs are not inputs.
  class TermEvidence
    include Rails.application.routes.url_helpers

    MAX_FACTS_PER_SECTION = 8

    attr_reader :facts, :selection_review

    def initialize(member, period: ResidentContent::CouncilPeriod.new(member))
      @member = member
      @period = period
      statements = CampaignStatement.current_for(member)
      start = period.selected&.started_on
      prior_start = period.periods.map(&:started_on).find { |date| start && date < start }
      campaign_on = statements.map { |s| s.campaign_source_version.election_on }.select do |date|
        start && date <= start && (!prior_start || date > prior_start)
      end.max
      @statements = statements.select { |s| s.campaign_source_version.election_on == campaign_on }
      @minutes = PromiseMinutes.new(member, period.range) if period.range
      @attendance = ResidentContent::CouncilAttendance.new(member, period: @period.selected).call
      campaign = campaign_facts
      @facts = (campaign + (tracked? ? council_facts : [])).uniq
    end

    def tracked?
      @tracked_statements.any?
    end

    # A rejected attribution can also appear in the generated overview. Use
    # saved campaign wording and individually recorded votes for a partial review.
    def sourced_overview(sentences)
      cited = Array(sentences).grep(Hash).flat_map { |row| Array(row["evidence"]) }.select { |id| id.is_a?(Integer) && id.between?(1, facts.size) }
      ordered = (cited + (1..facts.size).to_a).uniq
      campaign = ordered.find { |id| facts[id - 1][:promise_words].present? }
      votes = ordered.select { |id| facts[id - 1][:kind] == "Member vote" }.first(2)
      [ campaign, *votes ].compact.map do |id|
        fact = facts.fetch(id - 1)
        { text: fact[:overview_text] || fact.fetch(:text), facts: [ fact_keys.fetch(id - 1) ], sources: fact.fetch(:sources) }
      end
    end

    def fact_keys
      @fact_keys ||= @facts.map { |fact| Digest::SHA256.hexdigest(fact.slice(:kind, :text, :dates, :promise_words, :position, :identity).to_json) }
    end

    def digest
      judgments = @facts.zip(fact_keys).filter_map do |fact, key|
        scope = fact.slice(:undertaking, :record_test, :matched_positions, :opposed_positions, :advanced_positions, :unclear_positions, :reviewed_status, :reviewed_on, :city_outcome, :outcome_quote, :outcome_state).compact_blank
        [ key, scope ] if scope.any?
      end
      Digest::SHA256.hexdigest([ fact_keys.uniq.sort, judgments.sort_by(&:first) ].to_json)
    end

    private

    def campaign_facts
      platform = ResidentContent::CampaignPlatform.new(@statements, reviewed_only: true)
      @selection_review = platform.selection_review
      @platform_items = platform.items
      @tracked_statements = platform.items.flat_map { |item| item.fetch(:statements) }.uniq
      ActiveRecord::Associations::Preloader.new(records: @tracked_statements, associations: :related_topics).call
      positions = platform.items.map do |item|
        records = item.fetch(:statements)
        text = [ item.fetch(:description), *item[:qualifications] ].compact_blank.uniq.join(" ")
        campaign_fact(records, text).merge(position: item.fetch(:heading), overview_text: item.fetch(:description), undertaking: item[:undertaking], record_test: item[:record_test]).compact
      end
      reports = platform.items.flat_map do |item|
        item.fetch(:reports, []).map do |report|
          reviewed_on = report["reviewed_on"] || ResidentContent::CampaignPlatform::EDITION["findings_reviewed_on"] if report["finding_status"]
          { kind: "Public record", position: item.fetch(:heading), dates: Array(report["reviewed_on"]).presence,
            reviewed_status: report["finding_status"], reviewed_on: reviewed_on, text: report.fetch("text"), sources: report.fetch("sources").map { |s| source(s.fetch("label"), s.fetch("url")) } }
        end
      end
      excerpts = @minutes ? platform.items.flat_map { |item| @minutes.for_position(item) } : []
      positions.uniq.sort_by { |fact| fact[:text] } + reports.uniq.sort_by { |fact| fact[:text] } + excerpts
    end

    def campaign_fact(records, text)
      versions = records.map(&:campaign_source_version).uniq
      commitments = records.select { |row| row.data["supporting_quote"].present? }
        .sort_by { |row| [ row.data.fetch("supporting_quote"), row.campaign_source_version.source_url ] }
      words = commitments.map do |row|
        row.data.slice("supporting_quote", "conditions", "timeframe").compact_blank.transform_values(&:squish)
      end
      # Keep the representative quote's publication among the visible sources.
      ordered = ([ commitments.first&.campaign_source_version ].compact + versions.sort_by(&:source_url)).uniq
      sources = ordered.first(4).map { |v| source([ v.publisher, v.published_on ].compact.join(" · "), v.source_url) }
      if (time = commitments.first&.forum_clip_times&.dig(:answer))
        sources.first[:answer_ms] = time
      end
      { kind: "#{versions.first.election_on.year} campaign", dates: versions.filter_map(&:published_on).uniq.sort,
        text: text.squish.truncate(750), promise_words: words.uniq, sources: sources }
    end

    def council_facts
      return [] unless @period.selected && @attendance

      relevant_topics = Set.new
      votes = vote_facts(relevant_topics)
      actions = member_actions(relevant_topics)
      comparisons = direct_issue_comparisons.uniq.sort_by { |fact| [ fact.fetch(:dates), fact.fetch(:text) ] }.reverse
      contested = (votes + comparisons).flat_map { |fact| Array(fact[:opposed_positions]) }.uniq
      city = comparisons.select { |fact| fact[:city_outcome] || %w[rejected deferred].include?(fact[:outcome_state]) }
        .group_by { |fact| [ fact[:position], fact[:city_outcome] ] }.values.map { |items| items.max_by { |fact| fact.fetch(:dates).max } }
      include_conflicting_actions(votes, contested) + newest(actions) + newest(issue_outcomes(relevant_topics)) + (city + include_conflicting_actions(comparisons, contested)).uniq
    end

    def direct_votes
      matches = ResidentContent::CampaignActions.new(@member, statements: @statements, council_attendance: @attendance).call
      result = Hash.new { |h, k| h[k] = [] }
      @tracked_statements.each do |statement|
        matches.fetch(statement.id, []).each do |row|
          label = row.dig(:focus, "heading") || statement.data["summary"]
          result[row.fetch(:vote).id] << { heading: comparison_heading(statement, row), effect: row[:motion_effect], text: [ label, row.fetch(:reason) ].compact_blank.join(" — ") }
        end
      end
      result
    end

    def comparison_heading(statement, row)
      return row.dig(:focus, "heading") if row.dig(:focus, "heading").present?

      headings = @platform_items.select { |item| item.fetch(:comparable).include?(statement) }.pluck(:heading).uniq
      headings.sole if headings.one?
    end

    def vote_facts(relevant_topics)
      direct = direct_votes
      votes = ResidentContent::OfficialProfile.new(@member, council_meeting_ids: @attendance.fetch(:meeting_ids)).votes
      ActiveRecord::Associations::Preloader.new(records: votes.map(&:motion), associations: [
        { meeting: :meeting_documents }, { decision_observation: :minutes_extraction }
      ]).call
      ranked = votes.filter_map do |vote|
        motion = vote.motion
        next unless vote.value.in?(%w[yes no]) && ResidentContent::OfficialProfile.substantive_description?(motion.description)
        topics = motion.agenda_item&.agenda_item_topics.to_a.map(&:topic).select(&:approved?)
        counts = motion.votes.map(&:value).tally
        comparison = direct.fetch(vote.id, [])
        divided = counts.key?("no") && counts.key?("yes")
        impact = topics.map { |t| t.resident_impact_score.to_i }.max.to_i
        next unless comparison.any? || divided || impact >= 4
        relevant_topics.merge(topics.map(&:id))
        result = "Member voted #{vote.value}. Council result: #{motion.outcome.presence || "unrecorded"} (#{counts.fetch("yes", 0)} yes, #{counts.fetch("no", 0)} no)."
        detail = [ result, motion.description, motion.agenda_item&.display_context_title, *comparison.pluck(:text).uniq.sort ].compact_blank.uniq.join(" ")
        minutes = ResidentContent::VoteMinutes.for(motion)
        fact = meeting_fact("Member vote", motion.meeting, detail, minutes&.fetch(:source_url), minutes&.fetch(:label))
        subject = (motion.agenda_item&.title.presence || motion.description).to_s.sub(/\A\d{2}-\d{3}\s+/, "")
        action = motion.description.to_s.squish
        wording = [ subject, action ].compact_blank.uniq.join(" — ")
        fact[:overview_text] = "#{motion.meeting.starts_at.to_date.to_fs(:long)} · #{wording}. #{@member.name} voted #{vote.value}. #{motion.outcome&.humanize || "Outcome unrecorded"} (#{counts.fetch("yes", 0)} yes, #{counts.fetch("no", 0)} no)."
        headings = comparison.pluck(:heading).compact.uniq.sort
        fact[:matched_positions] = headings if headings.any?
        unclear = comparison.reject { |entry| %w[advances opposes].include?(entry[:effect]) }.pluck(:heading).compact.uniq.sort
        fact[:unclear_positions] = unclear if unclear.any?
        %w[advances opposes].each do |effect|
          positions = comparison.select { |entry| entry[:effect] == effect }.pluck(:heading).compact.uniq.sort
          next if positions.empty?
          supports = (effect == "advances") == (vote.value == "yes")
          key = supports ? :advanced_positions : :opposed_positions
          fact[key] = positions
        end
        [ [ comparison.any? ? 1 : 0, divided ? 1 : 0, impact, motion.meeting.starts_at, detail ], fact ]
      end
      ranked.sort_by(&:first).reverse.map(&:last).uniq
    end

    def include_conflicting_actions(ranked, contested)
      # Keep both sides of a contested position even when unrelated divided
      # votes outrank it. One vote may cover several positions.
      dated = ranked.sort_by { |fact| fact.fetch(:dates).max }.reverse
      sides = contested.flat_map do |heading|
        %i[opposed_positions advanced_positions].filter_map { |key| dated.find { |fact| Array(fact[key]).include?(heading) } }
      end.uniq
      sides + (ranked - sides).first([ MAX_FACTS_PER_SECTION - sides.size, 0 ].max)
    end

    def member_actions(relevant_topics)
      actions = ResidentContent::RecordedActions.new(@member, period: @period).call
      actions.filter_map do |row|
        evidence = row.fetch(:evidence)
        next unless ResidentContent::OfficialProfile.substantive_description?(evidence.fetch("summary"))
        relevant_topics.merge(row.fetch(:topics).map(&:id))
        url = row.dig(:citation, :source_url)
        fact = meeting_fact("Member action", row.fetch(:meeting), evidence.values_at("summary", "quote").compact.join(" "), url)
        headings = @platform_items.filter_map do |item|
          review = item[:reviewed_action]
          item[:heading] if review && review["minutes_url"] == url && review["quote"] == evidence["quote"]
        end
        fact[:matched_positions] = headings.uniq.sort if headings.any?
        fact
      end
    end

    def issue_outcomes(relevant_topics)
      updates = ResidentContent::IssueUpdates.new(@member, period: @period, attendance: @attendance, statements: @tracked_statements).call
      updates.filter_map do |row|
        next unless row.fetch(:topics).any? { |topic| relevant_topics.include?(topic.id) }
        evidence = row.fetch(:evidence)
        minutes = Array(row[:citations]).find { |citation| citation[:source_type].in?(%w[minutes_pdf minutes_html]) }
        next if row.key?(:citations) && (evidence["status"] != "decision" || !minutes)
        url = row.dig(:citation, :source_url) || minutes&.dig(:source_url)
        meeting_fact("Issue outcome, no personal credit", row.fetch(:meeting), evidence.values_at("subject", "status", "summary", "conditions").compact_blank.join(". "), url)
      end
    end

    def direct_issue_comparisons
      matches = ResidentContent::CampaignIssueEvidence.new(@member, statements: @statements).call
      @tracked_statements.flat_map do |statement|
        matches.fetch(statement.id, []).filter_map do |row|
          meeting = row.fetch(:meeting)
          next unless @period.range.cover?(meeting.starts_at)
          position = comparison_heading(statement, row)
          label = row.dig(:focus, "heading") || statement.data.fetch("summary")
          detail = [ label, row.fetch(:reason), row.dig(:evidence, "summary"), row.dig(:evidence, "conditions") ].compact_blank.uniq.join(" ")
          kind = row[:kind] == "action" ? "Member work on campaign position" : "City outcome on campaign position"
          fact = meeting_fact(kind, meeting, detail, row.dig(:citation, :source_url))
          if row[:kind] == "outcome" && position
            fact.merge!(position: position, outcome_state: row.dig(:evidence, "status"))
          end
          if row[:city_outcome] && position && row[:source_quote].present?
            occurred_on = Date.iso8601(row.fetch(:outcome_on))
            if @period.range.cover?(occurred_on.in_time_zone) && occurred_on <= meeting.starts_at.to_date
              fact.merge!(position: position, city_outcome: row[:city_outcome], outcome_quote: row[:source_quote],
                outcome_reason: row.fetch(:reason), dates: [ occurred_on ])
            end
          end
          if position
            fact[:matched_positions] = [ position ]
            if row[:kind] == "action"
              field = { "advances" => :advanced_positions, "opposes" => :opposed_positions }.fetch(row[:action_effect], :unclear_positions)
              fact[field] = [ position ]
            end
          end
          fact
        end
      end
    end

    def newest(rows)
      rows.uniq.sort_by { |fact| [ fact.fetch(:dates), fact.fetch(:text) ] }.last(MAX_FACTS_PER_SECTION)
    end

    def meeting_fact(kind, meeting, text, url = nil, label = nil)
      date = meeting.starts_at.to_date
      { kind: kind, dates: [ date ], text: text.squish.truncate(900),
        sources: [ source([ date, meeting.body_name, label ].compact.join(" · "), url.presence || meeting_path(meeting)) ] }
    end

    def source(label, url)
      { label: label, url: url }
    end
  end
end
