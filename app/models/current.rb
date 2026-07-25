class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :site_access_mode
  delegate :user, to: :session, allow_nil: true
end
