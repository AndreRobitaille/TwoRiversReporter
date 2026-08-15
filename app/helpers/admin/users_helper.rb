module Admin
  module UsersHelper
    ACCOUNT_STATUS = {
      "active" => { label: "Approved", variant: "success", row_state: "ok" },
      "rejected" => { label: "Denied", variant: "danger", row_state: "danger" },
      "pending" => { label: "Pending", variant: "warning", row_state: "warn" }
    }.freeze
    UNKNOWN_ACCOUNT_STATUS = { label: "Unknown", variant: "default", row_state: "warn" }.freeze

    APPLICATION_STATUS = {
      "email_pending" => { label: "Awaiting application", variant: "warning" },
      "submitted" => { label: "Ready for review", variant: "warning" },
      "approved" => { label: "Approved", variant: "success" },
      "rejected" => { label: "Denied", variant: "danger" }
    }.freeze
    UNKNOWN_APPLICATION_STATUS = { label: "Unknown", variant: "default" }.freeze

    def account_status_label(user)
      account_status(user)[:label]
    end

    def account_status_variant(user)
      account_status(user)[:variant]
    end

    def account_row_state(user)
      account_status(user)[:row_state]
    end

    def membership_application_status_label(application)
      application_status(application)[:label]
    end

    def membership_application_status_variant(application)
      application_status(application)[:variant]
    end

    private

      def account_status(user)
        ACCOUNT_STATUS.fetch(user.status, UNKNOWN_ACCOUNT_STATUS)
      end

      def application_status(application)
        APPLICATION_STATUS.fetch(application.status, UNKNOWN_APPLICATION_STATUS)
      end
  end
end
