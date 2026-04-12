module MembersHelper
  def attendance_sentence(attendance)
    pct = attendance[:pct]
    sentence = "Present at #{attendance[:present]} of #{attendance[:total]} recorded meetings (#{pct}%)"

    if attendance[:avg_rate]
      diff = pct - attendance[:avg_rate]
      if diff > 5
        sentence += " — above the #{attendance[:avg_rate]}% average across all officials"
      elsif diff < -5
        sentence += " — below the #{attendance[:avg_rate]}% average across all officials"
      else
        sentence += " — near the #{attendance[:avg_rate]}% average across all officials"
      end
    end

    sentence + "."
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
