ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # fixtures :all

    # Simple mock helper if needed
    def stub_request(url, headers = {}, &block)
      # Implementation depends on needs, but maybe we just use Minitest::Mock in individual tests
    end

    # Seeds prompt templates needed by OpenAiService.
    # Loads the seed data and the populate rake task data.
    # Call in setup for tests that exercise OpenAiService methods.
    def seed_prompt_templates
      require_relative "../lib/prompt_template_data"
      require_relative "support/prompt_template_seeds"
      PromptTemplateSeeds.create_all!
    end

    def sign_in_as_admin(user = nil)
      user ||= instance_variable_get(:@admin)
      sign_in_as(user)
    end

    def sign_in_as(user = nil)
      user ||= instance_variable_get(:@user)
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0) unless user.passkey_credentials.exists?

      session = Session.create!(user: user, user_agent: "test", ip_address: "127.0.0.1", last_seen_at: Time.current)
      jar = ActionDispatch::TestRequest.create.cookie_jar
      jar.signed[:session_id] = session.id
      cookies[:session_id] = jar[:session_id]
    end
  end
end
