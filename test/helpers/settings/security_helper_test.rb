require "test_helper"

class Settings::SecurityHelperTest < ActionView::TestCase
  include Settings::SecurityHelper

  test "a browser and platform pair renders as a readable phrase" do
    assert_equal "Chrome on Mac", describe_known_context_device("chrome|macintosh")
  end

  test "a platform with no friendly name falls back to a capitalized version of itself" do
    assert_equal "Opera on Someplatform", describe_known_context_device("opera|someplatform")
  end

  test "a fingerprint with no platform half renders the browser alone" do
    assert_equal "Chrome", describe_known_context_device("chrome")
  end

  test "nil renders as unknown rather than raising" do
    assert_equal "Unknown browser", describe_known_context_device(nil)
  end

  test "a blank string renders as unknown rather than raising" do
    assert_equal "Unknown browser", describe_known_context_device("")
  end
end
