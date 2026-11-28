class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :site_access_mode, :election_publication
  delegate :user, to: :session, allow_nil: true
end
