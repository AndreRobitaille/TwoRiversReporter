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

  def campaign_member_vote(vote)
    case vote.value
    when "yes" then "Voted yes"
    when "no" then "Voted no"
    when "abstain" then "Abstained"
    when "absent" then "Absent"
    else "Vote not recorded"
    end
  end

  def campaign_action_text(motion)
    description = motion.description.to_s.strip
    title = motion.agenda_item&.title.to_s.strip
    return title.presence || "Motion wording unavailable." if description.blank?

    action = description.sub(/\AMotion to\s+/i, "").sub(/\Awaive (?:the )?reading and\s+/i, "")
    if title.present? && action.match?(/\A(?:adopt|approve) (?:the )?(?:resolution|ordinance|item)(?:,? as recommended by [^.]+)?\.?\z/i)
      subject = title.sub(/\A\d[\d-]*\s+/, "").sub(/\AResolution\s+/i, "")
      verb = { "Adopting" => "Adopt", "Declaring" => "Declare", "Approving" => "Approve", "Authorizing" => "Authorize", "Amending" => "Amend" }
      first_word = subject.split.first
      action = if verb.key?(first_word)
        subject.sub(first_word, verb.fetch(first_word))
      elsif subject.match?(/\AOrdinance\b/i)
        "#{action.split.first} #{subject}"
      else
        "#{action.sub(/,? as recommended by .*/i, '').delete_suffix('.')}: #{subject}"
      end
      # This is a source-title excerpt, not a newly generated explanation.
      # Keep the full agenda subject and motion together in the disclosure.
      action = action.sub(/\s+for the purposes of\b.+\z/i, "…") if action.length > 120
      action = action.truncate(120, separator: " ")
    end
    action.sub(/\A./) { |letter| letter.upcase }
  end

  def campaign_council_results(votes)
    outcomes = votes.map { |vote| vote.motion.outcome.presence || "not recorded" }
    if outcomes.uniq.one?
      subject = votes.one? ? "The motion" : "Both motions"
      result = outcomes.first
      return "The Council result was not recorded." if result == "not recorded"

      if result.in?(%w[passed failed])
        "#{subject} #{result}."
      else
        "Recorded Council result: #{result.downcase}."
      end
    else
      votes.map.with_index { |vote, index| "#{index == 0 ? 'The first motion' : 'The second motion'}: #{vote.motion.outcome.presence || 'result not recorded'}." }.join(" ")
    end
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
end
