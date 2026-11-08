module MembersHelper
  # Use the same current-office priority and committee ordering as the page.
  def member_profile_role(current_position, memberships)
    return current_position.title if current_position

    membership = memberships.first
    return "Committee Member" unless membership

    role = membership_badges(membership, include_default: true).first.fetch(:label)
    "#{membership.committee.name} #{role}"
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
      actions.sort_by! do |row|
        row[:vote] ? row.fetch(:vote).motion.meeting.starts_at.to_date.iso8601 : row.dig(:evidence, "occurred_on") || row.fetch(:reported_on).iso8601
      end
      actions.reverse!
      [ statement, actions ] if actions.any?
    end
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
