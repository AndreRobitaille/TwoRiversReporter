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

    # Creates a signed-in session whose recorded context matches what an
    # integration request actually sends: remote_ip "127.0.0.1" and no
    # User-Agent header. A session stamped with anything else is treated as
    # coming from a new network or browser and is challenged.
    #
    # Pass ip_address:/user_agent: to build a session deliberately anchored
    # somewhere else — that is how a context mismatch is set up in a test.
    def sign_in_as(user = nil, ip_address: "127.0.0.1", user_agent: nil)
      user ||= instance_variable_get(:@user)
      user.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "public-key", sign_count: 0) unless user.passkey_credentials.exists?

      session = Session.create!(
        user: user,
        user_agent: user_agent,
        ip_address: ip_address,
        ip_prefix: NetworkPrefix.for(ip_address),
        device_fingerprint: DeviceFingerprint.for(user_agent),
        reauthenticated_at: Time.current,
        last_seen_at: Time.current
      )

      sign_in_with_session(session)
      session
    end

    def sign_in_with_session(session)
      jar = ActionDispatch::TestRequest.create.cookie_jar
      jar.signed[:session_id] = session.id
      cookies[:session_id] = jar[:session_id]
      session
    end
  end
end
