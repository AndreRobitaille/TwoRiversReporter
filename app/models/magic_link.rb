class MagicLink < ApplicationRecord
  belongs_to :user

  class InvalidToken < StandardError; end

  attr_accessor :raw_token

  scope :for_token, ->(token) { where(token_digest: MagicLink.send(:digest_token, token)) }

  scope :usable, -> { where(used_at: nil).where("expires_at > ?", Time.current) }

  def self.create_for!(user, purpose:, expires_at: 15.minutes.from_now)
    raw_token = SecureRandom.urlsafe_base64(32)

    create!(
      user: user,
      purpose: purpose,
      expires_at: expires_at,
      token_digest: digest_token(raw_token)
    ).tap { |magic_link| magic_link.raw_token = raw_token }
  end

  def self.consume!(token, purpose:)
    digest = digest_token(token)

    transaction do
      magic_link = lock.find_by(token_digest: digest, purpose: purpose)
      raise InvalidToken unless magic_link&.unused? && magic_link.unexpired? && magic_link.user.active_for_authentication?

      magic_link.update!(used_at: Time.current)
      magic_link
    end
  rescue ActiveRecord::RecordNotFound
    raise InvalidToken
  end

  def self.confirmable?(token, purpose:)
    for_token(token)
      .where(purpose: purpose)
      .usable
      .joins(:user)
      .where(users: { status: "active", disabled_at: nil })
      .exists?
  end

  def unused?
    used_at.blank?
  end

  def unexpired?
    expires_at.future?
  end

  def self.digest_token(token)
    OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, token.to_s)
  end
  private_class_method :digest_token
end
