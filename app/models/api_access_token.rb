class ApiAccessToken < ApplicationRecord
  PREFIX = "trr"
  PUBLIC_ID_BYTES = 12
  SECRET_BYTES = 32
  LAST_USED_WRITE_INTERVAL = 15.minutes
  METADATA_COLUMNS = %i[id user_id public_id display_hint name expires_at last_used_at revoked_at created_at updated_at].freeze

  belongs_to :user, inverse_of: :api_access_tokens

  normalizes :name, with: ->(value) { value.strip }
  validates :public_id, :secret_digest, :display_hint, :name, :expires_at, presence: true
  validates :public_id, uniqueness: true
  validates :name, length: { maximum: 80 }

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }
  scope :unexpired_and_unrevoked, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }
  scope :metadata_only, -> { select(*METADATA_COLUMNS) }

  def self.issue!(user:, name:, expires_in:, request: nil)
    raise ArgumentError, "An active account is required." unless user.active_for_authentication?

    secret = SecureRandom.hex(SECRET_BYTES)
    transaction do
      token = create!(user: user, name: name, public_id: SecureRandom.hex(PUBLIC_ID_BYTES),
        secret_digest: digest(secret), display_hint: secret.last(4), expires_at: expires_in.from_now)
      AuditEvent.record!(actor: user, action: "api_key.create", subject: token, label: token.name,
        request: request, metadata: { public_id: token.public_id, expires_at: token.expires_at.iso8601 })
      [ token, [ PREFIX, token.public_id, secret ].join("_") ]
    end
  end

  def self.authenticate(plaintext)
    match = plaintext.to_s.match(/\Atrr_([0-9a-f]{24})_([0-9a-f]{64})\z/)
    token = includes(:user).find_by(public_id: match[1]) if match
    candidate = digest(match ? match[2] : "invalid credential")
    stored = token&.secret_digest || digest("missing credential")
    valid = ActiveSupport::SecurityUtils.secure_compare(stored, candidate)
    return unless token && valid && token.active?

    token.touch_last_used_if_needed
    token
  end

  def self.digest(secret)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, secret)
  end

  def active?
    state == :active
  end

  def state
    return :revoked if revoked_at.present?
    return :expired if expires_at <= Time.current
    return :suspended unless user.active_for_authentication?

    :active
  end

  def revoke!(actor:, request: nil)
    with_lock do
      return if revoked_at.present?

      update!(revoked_at: Time.current)
      AuditEvent.record!(actor: actor, action: "api_key.revoke", subject: self, label: name,
        request: request, metadata: { public_id: public_id })
    end
  end

  def touch_last_used_if_needed
    return if last_used_at && last_used_at >= LAST_USED_WRITE_INTERVAL.ago

    self.class.where(id: id).where("last_used_at IS NULL OR last_used_at < ?", LAST_USED_WRITE_INTERVAL.ago)
      .update_all(last_used_at: Time.current)
  end
end
