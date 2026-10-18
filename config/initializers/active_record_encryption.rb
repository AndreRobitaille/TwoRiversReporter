require "base64"

# Development and test have no encryption credentials, so derive stable keys
# from secret_key_base. Rails 8.1 does not copy credentials onto
# config.active_record.encryption. It applies them to
# ActiveRecord::Encryption.config when active_record/encryption loads.

Rails.application.configure do
  config.active_record.encryption.support_unencrypted_data = true

  if config.active_record.encryption.primary_key.blank? && !Rails.env.production?
    secret = Rails.application.secret_key_base || ENV["SECRET_KEY_BASE"] || "development_secret_fallback_1234567890"
    generator = ActiveSupport::KeyGenerator.new(secret, hash_digest_class: OpenSSL::Digest::SHA1)

    config.active_record.encryption.primary_key = Base64.strict_encode64(generator.generate_key("active_record_encryption.primary_key", 32))
    config.active_record.encryption.deterministic_key = Base64.strict_encode64(generator.generate_key("active_record_encryption.deterministic_key", 32))
    config.active_record.encryption.key_derivation_salt = Base64.strict_encode64(generator.generate_key("active_record_encryption.key_derivation_salt", 32))
  end
end

if Rails.env.production?
  ActiveSupport.on_load(:active_record_encryption) do
    unless ActiveRecord::Encryption.config.has_primary_key?
      Rails.logger.warn "Active Record encryption keys are missing!"
    end
  end
end
