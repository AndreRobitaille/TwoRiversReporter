require "test_helper"

# Proves the controller's two rate limits count into separate buckets.
#
# The test environment's cache is a :null_store, whose #increment returns nil,
# so rate limiting is inert in tests by default — and the store each rate_limit
# declaration uses is captured when the class body runs, which means it cannot
# be swapped afterwards from outside. The probe below reaches the one seam that
# is left: ActionController::RateLimiting#rate_limiting, which receives the
# store on every request. It substitutes a counting store *only* while a test
# has asked for one, so nothing else in the suite changes behaviour, and it
# forwards the real declared name:, scope: and by: values to the real Rails
# implementation. What is under test is this controller's declarations, not
# Rails' key building.
module RateLimitProbe
  def rate_limiting(**kwargs)
    probe_store = Thread.current[:rate_limit_probe_store]
    kwargs[:store] = probe_store if probe_store
    super(**kwargs)
  end
end
ReauthenticationsController.prepend(RateLimitProbe)

class ReauthenticationRateLimitTest < ActionDispatch::IntegrationTest
  LIMIT = 10

  setup do
    @user = User.create!(email_address: "throttle@example.com", status: "active")
    Thread.current[:rate_limit_probe_store] = ActiveSupport::Cache::MemoryStore.new
  end

  teardown do
    Thread.current[:rate_limit_probe_store] = nil
  end

  # The consequence named in the review: a step-up costs two passkey requests
  # (options, then assertion), so five failed taps exhaust ten increments. On a
  # shared counter the email fallback then answers "Try again later." — the
  # fallback consumed by the failures it exists to rescue.
  test "exhausting the passkey limit leaves the magic-link fallback usable" do
    sign_in_as(@user)

    LIMIT.times { post passkey_options_reauthentication_url(format: :json) }
    post passkey_options_reauthentication_url(format: :json)
    assert_response :too_many_requests, "the passkey bucket must actually be exhausted for this test to mean anything"

    assert_difference -> { MagicLink.where(user: @user).count }, 1 do
      post magic_link_reauthentication_url
    end

    assert_nil flash[:alert],
      "the email fallback must not be throttled by failed passkey attempts"
  end

  test "exhausting the magic-link limit leaves the passkey path usable" do
    sign_in_as(@user)

    LIMIT.times { post magic_link_reauthentication_url }
    post magic_link_reauthentication_url
    assert_equal "Try again later.", flash[:alert],
      "the magic-link bucket must actually be exhausted for this test to mean anything"

    post passkey_options_reauthentication_url(format: :json)

    assert_response :success,
      "a step-up by passkey must not be throttled by requests for the email fallback"
  end

  test "each limit still throttles its own endpoints" do
    sign_in_as(@user)

    LIMIT.times { post magic_link_reauthentication_url }
    post magic_link_reauthentication_url

    assert_equal "Try again later.", flash[:alert],
      "naming the buckets must not stop either of them from counting"
  end
end
