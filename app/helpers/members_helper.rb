module MembersHelper
  MINUTES_LOCATIONS = YAML.safe_load_file(Rails.root.join("config/council_profile_minutes_locations.yml")).freeze

  def forum_clip_link(label, source_url, milliseconds)
    seconds = milliseconds.div(1000)
    link_to "#{label} at #{format("%d:%02d", *seconds.divmod(60))}", "#{source_url}&t=#{seconds}s"
  end

  def profile_term_heading
    return "Last campaign" unless @term_summary&.sentences.present?
    if (ends_on = ResidentContent::CouncilElection.scheduled_term_end(@member.name, @record_period.selected))
      return "Follow-through during the #{@term_summary.term_started_on.year}–#{ends_on.strftime("%y")} term"
    end

    "The term so far"
  end

  def promise_deductions(groups)
    labels = { "contrary" => "Reversal", "missed" => "Missed opportunity", "unresolved" => "Unfulfilled", "fell_short" => "Fell short" }
    labels.flat_map do |status, label|
      group = groups[status]
      next [] unless group

      points = CouncilProfiles::PromiseFollowThrough::POINTS.fetch(status)
      if group.many? && status != "contrary"
        caption = status == "missed" ? label.pluralize.downcase : label.downcase
        [ [ points * group.size, "#{group.size} #{caption}", "#promise-group-#{status}" ] ]
      else
        group.map do |item, index|
          subject = item["profile_subject"] || item["heading"].presence || item.fetch("label")
          [ points, "#{label} · #{subject}", "#promise-#{index + 1}" ]
        end
      end
    end
  end

  def profile_source_link(label, url, finding: nil, agenda_title: nil, **options)
    docket = agenda_title.to_s[/\A\d{2}-\d{3}\b/]
    location = MINUTES_LOCATIONS.find do |entry|
      entry.fetch("url") == url && (entry.fetch("finding") == finding || entry.fetch("items").key?(docket))
    end
    return link_to(label, url, **options) unless location

    items = location.fetch("items")
    items = items.slice(docket) if docket
    pages = items.values.flatten.uniq.sort
    locator = "#{"item".pluralize(items.size)} #{items.keys.to_sentence}, #{pages.one? ? 'p.' : 'pp.'} #{pages.join('–')}"
    link_to("#{url}#page=#{pages.first}", **options) do
      safe_join([ label, tag.span(locator, class: "minutes-locator") ], " · ")
    end
  end

  # Use the same current-office priority and committee ordering as the page.
  def member_profile_role(current_position, memberships)
    return current_position.title if current_position

    membership = memberships.first
    return "Committee Member" unless membership

    role = membership_badges(membership, include_default: true).first.fetch(:label)
    "#{membership.committee.name} #{role}"
  end

  def member_vote_profile_path(vote)
    @election_profile_ids ||= begin
      edition = ResidentContent::CouncilElection.current
      edition ? edition.member_ids_by_name.slice(*edition.terms_ending.keys).values : []
    end
    return member_path(vote.member) unless @election_profile_ids.include?(vote.member_id)

    member_path(vote.member, decision: vote.motion_id, anchor: "profile-decision")
  end

  def voting_record_path(**options)
    @separate_record ? record_member_path(@member, **options) : member_path(@member, **options)
  end

  def recorded_attendance_summary(counts)
    ResidentContent::CouncilAttendance::LABELS.filter_map do |status, label|
      "#{counts.fetch(status)} #{label.downcase}" if counts.fetch(status).positive?
    end.join(" · ")
  end

  def council_period_label(period)
    start_date = period.started_on.strftime("%b %-d, %Y")
    period.ended_on ? "#{start_date} – #{period.ended_on.strftime('%b %-d, %Y')}" : "Since #{start_date}"
  end

  def peer_vote_fraction(same, compared)
    compared.zero? ? "Not available" : "#{same} of #{compared}"
  end

  def vote_context(vote)
    # Prefer agenda item title over motion description — it's what the vote was actually about
    vote.motion.agenda_item&.title || vote.motion.description
  end

  def vote_split(motion)
    counts = motion.votes.each_with_object(Hash.new(0)) { |v, h| h[v.value] += 1 }
    "#{counts["yes"]}-#{counts["no"]}"
  end

  def vote_color_class(value)
    case value
    when "yes" then "vote-value--yes"
    when "no" then "vote-value--no"
    else "vote-value--neutral"
    end
  end

  def campaign_issue_actions(issue)
    issue.fetch(:statements).filter_map do |statement|
      actions = @campaign_actions.fetch(statement.id, []).select do |action|
        (action.fetch(:vote).motion.agenda_item.topics.map(&:id) & issue.fetch(:topic_ids)).any?
      end
      actions += (@campaign_issue_evidence || {}).fetch(statement.id, []).select do |record|
        (record.fetch(:topics).map(&:id) & issue.fetch(:topic_ids)).any?
      end
      [ statement, newest_campaign_actions(actions) ] if actions.any?
    end
  end

  def campaign_item_anchor(election, item)
    [ "campaign", election.iso8601, item.fetch(:kind), item.fetch(:heading), *item[:qualifications] ].compact_blank.join("-").parameterize
  end

  def campaign_item_actions(item)
    focus = item.slice(:heading, :description).stringify_keys
    actions = item.fetch(:statements).flat_map do |row|
      records = @campaign_actions.fetch(row.id, []) + @campaign_issue_evidence.fetch(row.id, [])
      records.select do |action|
        next action[:focus] == focus if action[:focus]
        next false unless item.fetch(:comparable).include?(row)
        next true unless (topic = item[:comparison_topic])
        topics = action[:topics] || action.fetch(:vote).motion.agenda_item&.topics.to_a
        topics.any? { |t| t.canonical_name == topic }
      end
    end
    newest_campaign_actions(actions.uniq do |action|
      action[:vote]&.id || [ action[:meeting].id, action[:kind], action[:evidence] ]
    end)
  end

  def newest_campaign_actions(actions)
    actions.sort_by do |row|
      date = row[:vote] ? row.fetch(:vote).motion.meeting.starts_at.to_date.iso8601 : row.dig(:evidence, "occurred_on") || row.fetch(:reported_on).iso8601
      # On the same date, show what this member did before general issue updates.
      [ date, row[:kind] == "outcome" ? 0 : 1 ]
    end.reverse
  end

  def campaign_decision_title(vote)
    member_decision_title(vote.motion)
  end

  def member_decision_title(motion)
    title = (motion.agenda_item&.title.presence || motion.description).to_s.sub(/\A\d{2}-\d{3}\s+/, "")
    # Application headings repeat the docket and applicant address. Keep the
    # requested assistance and named applicant; the full title stays in details.
    if application = title.match(/\AApplication for (.+?) by (.+?), \d.*\z/i)
      "#{application[1]} — #{application[2]}"
    else
      title.presence || "Motion description unavailable."
    end
  end

  def campaign_qualifications(statement)
    summary = " #{normalize_campaign_qualification(statement.data.fetch("summary"))} "
    { "conditions" => "Condition", "timeframe" => "Timing" }.filter_map do |field, label|
      text = statement.data[field]
      next if text.blank? || summary.include?(" #{normalize_campaign_qualification(text)} ")

      "#{label}: #{text}"
    end
  end

  private

  def normalize_campaign_qualification(text)
    text.downcase.gsub(/[[:punct:]]/, " ")
      .gsub(/\b(?:per|every|each)(?=\s+(?:calendar\s+)?(?:year|month|week|day)\b)/, "each").squish
  end
end
