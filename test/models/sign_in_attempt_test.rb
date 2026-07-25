# test/models/sign_in_attempt_test.rb
require "test_helper"

class SignInAttemptTest < ActiveSupport::TestCase
  test "a fresh address is not throttled" do
    assert_not SignInAttempt.throttled?("nobody@example.com")
  end

  test "an address is throttled after a recent attempt" do
    SignInAttempt.record!("someone@example.com")

    assert SignInAttempt.throttled?("someone@example.com")
  end

  test "the throttle expires after the window" do
    SignInAttempt.record!("someone@example.com")
    SignInAttempt.last.update!(created_at: 16.minutes.ago)

    assert_not SignInAttempt.throttled?("someone@example.com")
  end

  test "addresses are compared case-insensitively" do
    SignInAttempt.record!("Someone@Example.com")

    assert SignInAttempt.throttled?("someone@example.com")
  end
end
