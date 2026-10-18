require "test_helper"

class ActiveRecordEncryptionInitializerTest < ActiveSupport::TestCase
  setup do
    @app_encryption = Rails.application.config.active_record.encryption
    @saved_app = {
      primary_key: @app_encryption.primary_key,
      deterministic_key: @app_encryption.deterministic_key,
      key_derivation_salt: @app_encryption.key_derivation_salt,
      support_unencrypted_data: @app_encryption.support_unencrypted_data
    }
    encryption = ActiveRecord::Encryption.config
    @saved_encryption_primary = encryption.has_primary_key? ? encryption.primary_key : nil
    @saved_logger = Rails.logger
  end

  teardown do
    @saved_app.each { |key, value| @app_encryption.public_send(:"#{key}=", value) }
    ActiveRecord::Encryption.config.primary_key = @saved_encryption_primary
    Rails.logger = @saved_logger

    assert_equal derived_primary_key, ActiveRecord::Encryption.config.primary_key
  end

  test "derives stable encryption keys from secret_key_base outside production" do
    secret = Rails.application.secret_key_base || ENV["SECRET_KEY_BASE"] || "development_secret_fallback_1234567890"
    generator = ActiveSupport::KeyGenerator.new(secret, hash_digest_class: OpenSSL::Digest::SHA1)

    assert_equal encoded_key(generator, "active_record_encryption.primary_key"), @app_encryption.primary_key
    assert_equal encoded_key(generator, "active_record_encryption.deterministic_key"), @app_encryption.deterministic_key
    assert_equal encoded_key(generator, "active_record_encryption.key_derivation_salt"), @app_encryption.key_derivation_salt
    assert_equal true, @app_encryption.support_unencrypted_data
    assert ActiveRecord::Encryption.config.has_primary_key?
  end

  test "production does not warn when the encryption config has a primary key" do
    @app_encryption.primary_key = nil

    assert_not_includes reload_warnings, "Active Record encryption keys are missing!"
  end

  test "production warns when the encryption config has no primary key" do
    @app_encryption.primary_key = nil
    ActiveRecord::Encryption.config.primary_key = nil

    assert_includes reload_warnings, "Active Record encryption keys are missing!"
  end

  test "production warns when only the encryption config is missing a primary key" do
    ActiveRecord::Encryption.config.primary_key = nil

    assert_includes reload_warnings, "Active Record encryption keys are missing!"
  end

  private
    def reload_warnings
      io = StringIO.new
      Rails.logger = ActiveSupport::Logger.new(io)
      Rails.env.stub(:production?, true) do
        load Rails.root.join("config/initializers/active_record_encryption.rb")
      end
      io.string
    end

    def derived_primary_key
      secret = Rails.application.secret_key_base || ENV["SECRET_KEY_BASE"] || "development_secret_fallback_1234567890"
      generator = ActiveSupport::KeyGenerator.new(secret, hash_digest_class: OpenSSL::Digest::SHA1)
      encoded_key(generator, "active_record_encryption.primary_key")
    end

    def encoded_key(generator, salt)
      Base64.strict_encode64(generator.generate_key(salt, 32))
    end
end
