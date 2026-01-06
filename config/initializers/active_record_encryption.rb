require "base64"

# Configure Active Record Encryption for development/test without credentials.
# In production, these should be set via `bin/rails db:encryption:init` and credentials.

Rails.application.configure do
  config.active_record.encryption.support_unencrypted_data = true

  # Only derive keys if not already configured (e.g. by credentials)
  if config.active_record.encryption.primary_key.blank?
    if Rails.env.production?
      Rails.logger.warn "Active Record encryption keys are missing!"
    else
      # Derive stable keys from secret_key_base for dev/test
      secret = Rails.application.secret_key_base || ENV["SECRET_KEY_BASE"] || "development_secret_fallback_1234567890"
      generator = ActiveSupport::KeyGenerator.new(secret)

      config.active_record.encryption.primary_key = Base64.strict_encode64(generator.generate_key("active_record_encryption.primary_key", 32))
      config.active_record.encryption.deterministic_key = Base64.strict_encode64(generator.generate_key("active_record_encryption.deterministic_key", 32))
      config.active_record.encryption.key_derivation_salt = Base64.strict_encode64(generator.generate_key("active_record_encryption.key_derivation_salt", 32))
    end
  end
end
