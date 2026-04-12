module MembersHelper
  def attendance_sentence(attendance)
    parts = [ "Present at #{attendance[:present]} of #{attendance[:total]} recorded meetings" ]
    details = []
    details << "excused from #{attendance[:excused]}" if attendance[:excused] > 0
    details << "absent from #{attendance[:absent]}" if attendance[:absent] > 0
    parts << details.join(", ") if details.any?
    parts.join(". ") + "."
  end

  def vote_split(motion)
    counts = motion.votes.group(:value).count
    yes_count = counts["yes"] || 0
    no_count = counts["no"] || 0
    "#{yes_count}-#{no_count}"
  end

  def vote_color_class(value)
    case value
    when "yes" then "vote-value--yes"
    when "no" then "vote-value--no"
    else "vote-value--neutral"
    end
  end
end
