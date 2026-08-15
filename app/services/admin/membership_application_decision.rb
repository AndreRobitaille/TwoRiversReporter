module Admin
  class MembershipApplicationDecision
    class ReasonRequired < StandardError; end

    Snapshot = Data.define(
      :user_status,
      :user_disabled_at,
      :application_status,
      :reviewed_at,
      :reviewed_by_id,
      :decision_reason
    )

    def initialize(user:, reviewer:, reason:)
      @user_id = user.id
      @reviewer_id = reviewer.id
      @reason = reason.to_s.strip
    end

    def approve!
      require_reason!
      snapshot = nil

      ApplicationRecord.transaction do
        lock_records!
        snapshot = snapshot_state
        @magic_link = MagicLink.create_for!(@user, purpose: "sign_in")

        @user.update!(status: "active", disabled_at: nil)
        @application.update!(
          status: "approved",
          reviewed_at: Time.current,
          reviewed_by_id: @reviewer_id,
          decision_reason: @reason
        )
      end

      TransactionalEmail.application_approved(@user, @application, @magic_link).deliver_now
      @application
    rescue StandardError
      compensate!(snapshot, expected_status: "approved", magic_link: @magic_link)
      raise
    end

    def deny!
      require_reason!
      snapshot = nil

      ApplicationRecord.transaction do
        lock_records!
        snapshot = snapshot_state

        @user.update!(status: "rejected")
        @application.update!(
          status: "rejected",
          reviewed_at: Time.current,
          reviewed_by_id: @reviewer_id,
          decision_reason: @reason
        )
      end

      TransactionalEmail.application_denied(@user, @application).deliver_now
      @application
    rescue StandardError
      compensate!(snapshot, expected_status: "rejected")
      raise
    end

    private

      def require_reason!
        return if @reason.present?

        raise ReasonRequired, "Enter a decision reason before approving or denying this application."
      end

      def lock_records!
        @user = User.lock.find(@user_id)
        @application = @user.membership_applications.reviewable.order(created_at: :desc).lock.first!
      end

      def snapshot_state
        Snapshot.new(
          user_status: @user.status,
          user_disabled_at: @user.disabled_at,
          application_status: @application.status,
          reviewed_at: @application.reviewed_at,
          reviewed_by_id: @application.reviewed_by_id,
          decision_reason: @application.decision_reason
        )
      end

      def compensate!(snapshot, expected_status:, magic_link: nil)
        return unless snapshot && @application

        ApplicationRecord.transaction do
          user = User.lock.find(@user_id)
          application = user.membership_applications.lock.find(@application.id)
          if decision_still_current?(application, expected_status)
            restore_snapshot!(user, application, snapshot)
            MagicLink.lock.find_by(id: magic_link&.id)&.destroy!
          end
        end
      end

      def restore_snapshot!(user, application, snapshot)
        user.update!(status: snapshot.user_status, disabled_at: snapshot.user_disabled_at)
        application.update!(
          status: snapshot.application_status,
          reviewed_at: snapshot.reviewed_at,
          reviewed_by_id: snapshot.reviewed_by_id,
          decision_reason: snapshot.decision_reason
        )
      end

      def decision_still_current?(application, expected_status)
        application.status == expected_status &&
          application.reviewed_by_id == @reviewer_id &&
          application.decision_reason == @reason
      end
  end
end
