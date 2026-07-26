module Admin
  class AuditEventsController < BaseController
    # No pagination: no admin index in this app paginates, `pagy_nav` is used
    # nowhere in the views, and a capped list is honest about being capped.
    # Revisit if the table ever gets big enough to matter.
    LIMIT = 200

    def index
      @audit_events = AuditEvent.includes(:actor).order(created_at: :desc).limit(LIMIT)
    end
  end
end
