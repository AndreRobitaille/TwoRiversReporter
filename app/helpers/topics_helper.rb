module TopicsHelper
  def topic_lifecycle_badge(status)
    css_class = case status
    when "active" then "badge--success"
    when "resolved" then "badge--info"
    when "recurring" then "badge--warning"
    when "dormant" then "badge--secondary"
    else "badge--default"
    end
    tag.span(status.humanize, class: "badge #{css_class}")
  end

  def signal_badge(type)
    css_class = "badge--default"
    label = case type
    when "deferral_signal" then "Deferral Observed"
    when "disappearance_signal" then "Disappearance Observed"
    when "cross_body_progression" then "Body Change"
    when "rules_engine_update" then "Status Update"
    else type.humanize
    end
    tag.span(label, class: "badge #{css_class} badge--outline", title: type.humanize)
  end

  def group_last_activity_label(last_activity_at)
    return "Not yet recorded" if last_activity_at.blank?

    "#{time_ago_in_words(last_activity_at)} ago"
  end
end
