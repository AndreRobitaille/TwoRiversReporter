module ApiKeysHelper
  def api_key_state_label(key)
    return "Suspended — account disabled" if key.state == :suspended && key.user.disabled_at.present?

    key.state.to_s.humanize
  end

  def api_key_state_variant(key)
    { active: "success", expired: "default", revoked: "default", suspended: "warning" }.fetch(key.state)
  end

  def api_key_date(time)
    time ? l(time, format: :long) : "Not used yet"
  end
end
