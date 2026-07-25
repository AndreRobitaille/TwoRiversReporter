class User < ApplicationRecord
  # Raised instead of quietly deleting the only account that can still reach the
  # admin area. Creating an admin requires already being one, so a site with
  # zero admins cannot be repaired through the UI at all.
  class LastAdminError < StandardError; end

  # Deliberately the stdlib regex rather than a hand-rolled RFC 5322 attempt.
  # The job here is to catch "asdf" before it is handed to the mail provider as
  # a recipient, not to adjudicate exotic-but-legal addresses; over-strict email
  # validation rejects real people.
  EMAIL_FORMAT = URI::MailTo::EMAIL_REGEXP

  has_many :sessions, dependent: :destroy
  has_many :magic_links, dependent: :destroy
  has_many :passkey_credentials, dependent: :destroy
  has_many :membership_applications, dependent: :destroy

  # Records that point at a user but must outlive them. Without these, deleting
  # a user raises ActiveRecord::InvalidForeignKey — every one of these columns
  # has a foreign key to users and none of them cascade at the database level.
  #
  # :nullify rather than :destroy in all three cases. Each row is somebody
  # else's record: an applicant's own application (which merely happens to name
  # this admin as its reviewer), site content, and a topic moderation audit
  # trail. Losing the pointer to a deleted account is acceptable; losing the row
  # is not. All three columns are nullable and all three inverse associations
  # are already declared `optional: true`.
  has_many :reviewed_membership_applications,
    class_name: "MembershipApplication", foreign_key: :reviewed_by_id,
    inverse_of: :reviewed_by, dependent: :nullify
  has_many :uploaded_generated_images,
    class_name: "GeneratedImage", foreign_key: :uploaded_by_id,
    inverse_of: :uploaded_by, dependent: :nullify
  has_many :topic_review_events, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  before_validation :backfill_passwordless_fields

  # Enforced on the model rather than in the controller because the controller
  # is not the only way a user gets destroyed: a console session or a rake task
  # would otherwise lock the owner out of their own site with one typo.
  #
  # `prepend` is an optimisation only — it runs the check before the
  # dependent-destroy callbacks so nothing is torn down needlessly. Correctness
  # comes from the surrounding transaction, which rolls the lot back either way,
  # so no test asserts on the ordering.
  before_destroy :refuse_to_leave_the_site_without_an_admin, prepend: true

  validates :email_address, presence: true, uniqueness: true

  # Format checking arrived in July 2026, after `email_field` had been the only
  # gate for months — and `email_field` is browser-side, so a crafted request
  # could already have stored junk. Same shape as MembershipApplication#street:
  # check it where it can actually be fixed (a new account, or a save that
  # touches the address) rather than blanket, which would make any pre-existing
  # bad row permanently unsaveable and so unreviewable by an admin. Nothing new
  # gets in without a real address either way.
  validates :email_address,
    format: { with: EMAIL_FORMAT, allow_blank: true, message: "is not a valid email address" },
    if: :email_address_changed?
  validates :status, inclusion: { in: %w[pending active rejected] }
  validates :webauthn_id, presence: true, uniqueness: true

  # Cheap pre-flight for controllers that must not let a malformed address reach
  # the throttle or the mail provider, and must not reveal that they rejected it.
  def self.deliverable_address?(value)
    value.to_s.match?(EMAIL_FORMAT)
  end

  # True when removing this account would leave the site with no admin at all,
  # which is unrecoverable: creating an admin requires already being one.
  def last_admin?
    return false unless admin?

    !User.where(admin: true).where.not(id: id).exists?
  end

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

  def refuse_to_leave_the_site_without_an_admin
    raise LastAdminError, "cannot delete the last admin account" if last_admin?
  end

  def backfill_passwordless_fields
    if new_record? && !@status_provided
      self.status = admin? ? "active" : "pending"
    elsif status.nil?
      self.status = admin? ? "active" : "pending"
    end
    self.webauthn_id ||= WebAuthn.generate_user_id
  end
end
