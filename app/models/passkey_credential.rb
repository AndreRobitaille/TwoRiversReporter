class PasskeyCredential < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key, presence: true
  validates :sign_count, numericality: { greater_than_or_equal_to: 0 }

  before_destroy :refuse_to_remove_last_usable_admin_passkey

  def self.for_user(user)
    where(user: user)
  end

  private

    def refuse_to_remove_last_usable_admin_passkey
      return unless user.admin? && user.active_for_authentication?

      User.with_admin_roster_lock do
        return if user.passkey_credentials.where.not(id: id).exists?
        return if User.usable_admins.where.not(id: user_id).exists?

        raise User::LastAdminError, "at least one active admin with a passkey must remain"
      end
    end
end
