module CouncilAiAuthorization
  extend ActiveSupport::Concern

  included do
    belongs_to :actor, class_name: "User", optional: true
    validates :original_actor_id, :authorized_at, :authorization_basis, presence: true
    before_validation(on: :create) { self.original_actor_id = actor_id }
    validate :authorized_administrator, on: :create
    validate :retained_authorization
    before_destroy { throw :abort }
  end

  private

  def authorized_administrator
    unless actor&.admin? && actor.active_for_authentication? && authorized_at && authorized_at <= Time.current
      errors.add(:base, "requires an active administrator and explicit authorization time")
    end
  end

  def retained_authorization
    mutable = self.class.column_names.include?("revoked_at") ? [ "revoked_at", "updated_at" ] : [ "updated_at" ]
    errors.add(:base, "cannot replace spending authorization") if persisted? && (changed - mutable).any?
    if persisted? && respond_to?(:revoked_at) && revoked_at_in_database && will_save_change_to_revoked_at?
      errors.add(:revoked_at, "cannot restore a revoked run")
    end
  end
end
