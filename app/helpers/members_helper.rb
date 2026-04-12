module MembersHelper
  def attendance_comparison(data)
    pct = data[:pct]
    text = "#{data[:present]} of #{data[:total]} (#{pct}%)"

    if data[:avg_rate]
      diff = pct - data[:avg_rate]
      if diff > 5
        text += " — above #{data[:avg_rate]}% avg"
      elsif diff < -5
        text += " — below #{data[:avg_rate]}% avg"
      else
        text += " — near #{data[:avg_rate]}% avg"
      end
    end

    text
  end

  def vote_context(vote)
    # Prefer agenda item title over motion description — it's what the vote was actually about
    vote.motion.agenda_item&.title || vote.motion.description
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
