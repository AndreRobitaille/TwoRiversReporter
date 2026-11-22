module Campaigns
  class ReviewedComparisons
    # The retained pair keys contain installation-specific document and meeting
    # identities. Match complete civic evidence before rebuilding a key.
    def self.export
      CampaignActionReview.where(status: "completed").includes(:meeting).flat_map do |review|
        original = review.data.fetch("matches").index_by { |match| match.fetch("key") }
        review.context.fetch("pairs").map do |pair|
          statement = CampaignStatement.find(pair.fetch("statement_id"))
          { "starts_at" => review.meeting.starts_at.iso8601, "source" => review.context.fetch("source").slice("source_url", "text_sha256"),
            "campaign_url" => statement.campaign_source_version.source_url, "sequence" => statement.sequence,
            "pair" => pair.except("key", "source_key", "statement_id", "campaign_version", "motion_id"),
            "match" => original.fetch(pair.fetch("key")).except("key"), "rejection" => review.rejected_pairs[ActionInput.key(pair)] }
        end
      end
    end

    def self.call(rows, actor:)
      raise ArgumentError, "Active administrator required" unless actor&.admin? && actor.active_for_authentication?
      groups = rows.group_by { |r| [ r.fetch("starts_at"), r.fetch("source") ] }
      imported = 0
      groups.each do |(starts_at, source), records|
        docs = MeetingDocument.joins(:meeting).where(meetings: { starts_at: Time.iso8601(starts_at) }, source_url: source.fetch("source_url"))
        docs = docs.select { |d| Digest::SHA256.hexdigest(d.extracted_text.to_s) == source.fetch("text_sha256") }
        next unless docs.one?
        document = docs.sole
        meeting = document.meeting
        meeting.with_lock do
          votes, issue = records.partition { |r| r.dig("pair", "rules") == ActionInput::RULES }
          imported += restore_votes(meeting, document, votes, actor)
          imported += restore_issue(meeting, document, issue, actor)
        end
      end
      { available: rows.length, resolved: imported, held: rows.length - imported }
    end

    def self.restore_votes(meeting, document, rows, actor)
      return 0 if rows.empty?
      minutes = Minutes::Input.new(meeting)
      return 0 unless document == minutes.document
      rows.count do |row|
        raw = row.fetch("pair")
        motions = meeting.motions.where(description: raw.fetch("motion")).select { |motion| motion.agenda_item&.display_context_title == raw["agenda"] }
        next unless motions.one?
        statement = find_statement(row)
        next unless statement && motions.sole.votes.exists?(member: statement.member)
        pair = raw.merge("source_key" => minutes.source_key, "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key,
          "motion_id" => motions.sole.id)
        restore(meeting, { "rules" => ActionInput::RULES, "source" => minutes.source_manifest, "minutes" => minutes.text }, pair, row, actor)
      end
    rescue Minutes::Input::Unavailable
      0
    end

    def self.restore_issue(meeting, document, rows, actor)
      return 0 if rows.empty?
      candidates = IssueEvidenceCandidates.all(meeting_id: meeting.id).select { |c| c.fetch(:review).meeting_document == document }
      rows.count do |row|
        statement = find_statement(row)
        next unless statement
        raw = row.fetch("pair")
        matches = candidates.select do |c|
          c.fetch(:statement) == statement && c.fetch(:evidence).except("agenda_item_id", "topic_ids") == raw.fetch("evidence") &&
            c.fetch(:kind) == raw.fetch("evidence_kind")
        end
        reviews = matches.pluck(:review).uniq
        next unless reviews.one?
        review = reviews.sole
        pair = raw.merge("source_key" => review.input_key, "statement_id" => statement.id, "campaign_version" => statement.campaign_source_version.version_key)
        context = IssueEvidenceInput.new(review, matches).context([])
        restore(meeting, context, pair, row, actor)
      end
    end

    def self.find_statement(row)
      version = CampaignSource.find_by(source_url: row.fetch("campaign_url"))&.current_version
      statement = version&.extraction&.campaign_statements&.find_by(sequence: row.fetch("sequence"), status: "accepted")
      statement if statement && statement.data.slice(*row.dig("pair", "statement").keys) == row.dig("pair", "statement")
    end

    def self.restore(meeting, context, pair, row, actor)
      key = ActionInput.key(pair)
      pair = pair.merge("key" => key)
      context = context.merge("pairs" => [ pair ])
      data = ActionMatches.new(context).parse({ matches: [ row.fetch("match").merge("key" => key) ] }.to_json)
      existing = CampaignActionReview.where(meeting: meeting).detect { |r| r.pair_keys.include?(key) }
      if existing
        return false unless existing.status == "completed" && existing.context.fetch("pairs").any? { |p| ActionInput.key(p) == key &&
          existing.data.fetch("matches").include?(row.fetch("match").merge("key" => p.fetch("key"))) }
      else
        existing = CampaignActionReview.create!(meeting: meeting, input_key: CouncilProfiles::ReserveAiSpend.request_digest(pairs: [ key ]),
          parameters: {}, context: context, data: data, status: "completed", completed_at: Time.current)
      end
      existing.reject_matches!(keys: [ key ], actor: actor, reason: row.fetch("rejection")) if row["rejection"].present?
      true
    end
    private_class_method :restore_votes, :restore_issue, :find_statement, :restore
  end
end
