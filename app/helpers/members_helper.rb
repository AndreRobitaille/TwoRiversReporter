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
