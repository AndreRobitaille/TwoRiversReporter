require "test_helper"

class SessionsAlwaysEmailTest < ActionDispatch::IntegrationTest
  test "an unknown address receives the no-account email" do
    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "stranger@example.com" }
    end

    assert_equal [ "no_account" ], sent.map(&:transactional_id)
    assert_redirected_to new_public_session_path
  end

  test "a pending applicant receives the pending email" do
    User.create!(email_address: "waiting@example.com", status: "pending", disabled_at: Time.current)

    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "waiting@example.com" }
    end

    assert_equal [ "application_pending" ], sent.map(&:transactional_id)
  end

  test "an active member receives a magic link" do
    User.create!(email_address: "member@example.com", status: "active")

    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "member@example.com" }
    end

    assert_equal 1, MagicLink.where(purpose: "sign_in").count
    assert_equal [ TransactionalEmail.magic_link_transactional_id ], sent.map(&:transactional_id)
  end

  test "all three branches produce an identical browser response" do
    User.create!(email_address: "member2@example.com", status: "active")
    User.create!(email_address: "waiting2@example.com", status: "pending", disabled_at: Time.current)

    bodies = with_forgery_protection do
      [ "member2@example.com", "waiting2@example.com", "nobody2@example.com" ].map do |email|
        SignInAttempt.delete_all
        get new_public_session_path
        token = response.body[/name="authenticity_token" value="([^"]*)"/, 1]

        stub_delivery([]) do
          post public_session_path, params: { email_address: email, authenticity_token: token }
        end
        follow_redirect!
        normalize_csrf_tokens(response.body)
      end
    end

    assert_equal 1, bodies.uniq.size, "responses must be indistinguishable across account states"
  end

  test "a throttled address sends no second email" do
    SignInAttempt.record!("stranger@example.com")

    sent = []
    stub_delivery(sent) do
      post public_session_path, params: { email_address: "stranger@example.com" }
    end

    assert_empty sent
    assert_redirected_to new_public_session_path
  end

  private

    # The test environment disables forgery protection, so the sign-in page
    # normally renders with no CSRF token at all. Enabling it here means the
    # identity assertion is made against the same markup production serves.
    def with_forgery_protection
      original = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = original
    end

    # Rails masks the CSRF authenticity token with a fresh random pad on every
    # render, so two byte-identical pages still carry different token strings.
    # Only those token values are blanked — the surrounding markup, the flash
    # message, and every other byte are compared strictly, so a genuine
    # per-account-state difference still fails the assertion.
    def normalize_csrf_tokens(body)
      body
        .gsub(/(<meta name="csrf-token" content=")[^"]*(")/, '\1CSRF\2')
        .gsub(/(name="authenticity_token" value=")[^"]*(")/, '\1CSRF\2')
    end

    def stub_delivery(collector)
      TransactionalEmail::Message.stub(:new, ->(**kwargs) {
        message = Struct.new(:email, :transactional_id, :data_variables, keyword_init: true).new(**kwargs)
        message.define_singleton_method(:deliver_now) { collector << self }
        message
      }) do
        yield
      end
    end
end
