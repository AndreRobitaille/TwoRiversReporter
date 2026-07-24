class User < ApplicationRecord
  has_many :sessions, dependent: :destroy
  has_many :magic_links, dependent: :destroy
  has_many :passkey_credentials, dependent: :destroy
  has_many :membership_applications, dependent: :destroy

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  before_validation :backfill_passwordless_fields

  validates :email_address, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[pending active rejected] }
  validates :webauthn_id, presence: true, uniqueness: true

  def active_for_authentication?
    status == "active" && disabled_at.blank?
  end

  def admin_access_ready?
    return false unless admin? && active_for_authentication?

    passkey_credentials.exists?
  end

  def passkey_prompt_dismissed?
    passkey_prompt_dismissed_until.present? && passkey_prompt_dismissed_until.future?
  end

  def status=(value)
    @status_provided = true
    super
  end

  def dismiss_passkey_prompt!
    update!(passkey_prompt_dismissed_until: 1.week.from_now)
  end

  private

  def backfill_passwordless_fields
    if new_record? && !@status_provided
      self.status = admin? ? "active" : "pending"
    elsif status.nil?
      self.status = admin? ? "active" : "pending"
    end
    self.webauthn_id ||= WebAuthn.generate_user_id
  end
end
