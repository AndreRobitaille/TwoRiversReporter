class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  encrypts :totp_secret

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true

  generates_token_for :password_reset, expires_in: 15.minutes do
    password_digest&.last(10)
  end

  def password_reset_token
    generate_token_for(:password_reset)
  end

  def password_reset_token_expires_in
    self.class.token_expires_in(:password_reset)
  end

  def self.find_by_password_reset_token!(token)
    find_by_token_for!(:password_reset, token)
  end

  def ensure_totp_secret!
    return totp_secret if totp_secret.present?

    update!(totp_secret: ROTP::Base32.random_base32(32))
    totp_secret
  end

  def totp_provisioning_uri
    return if totp_secret.blank?

    ROTP::TOTP.new(totp_secret, issuer: "TwoRiversReporter").provisioning_uri(email_address)
  end

  def valid_totp_code?(code)
    return false if totp_secret.blank?

    normalized = code.to_s.delete(" ")
    ROTP::TOTP.new(totp_secret, issuer: "TwoRiversReporter").verify(
      normalized,
      drift_behind: 30,
      drift_ahead: 30
    ).present?
  end

  def regenerate_recovery_codes!
    codes = Array.new(12) do
      left = SecureRandom.alphanumeric(4).upcase
      right = SecureRandom.alphanumeric(4).upcase
      "#{left}-#{right}"
    end

    digests = codes.map { |c| BCrypt::Password.create(c) }
    update!(recovery_codes_digest: digests)

    codes
  end

  def consume_recovery_code(code)
    return false if recovery_codes_digest.empty?

    normalized = code.to_s.strip.upcase
    remaining = recovery_codes_digest.dup

    matching_digest = remaining.find do |digest|
      BCrypt::Password.new(digest) == normalized
    rescue BCrypt::Errors::InvalidHash
      false
    end

    return false unless matching_digest

    remaining.delete(matching_digest)
    update!(recovery_codes_digest: remaining)

    true
  end
end
