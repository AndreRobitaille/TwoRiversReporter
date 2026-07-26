require "test_helper"

class DeviceFingerprintTest < ActiveSupport::TestCase
  CHROME_MAC_140 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36".freeze
  CHROME_MAC_141 = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36".freeze
  SAFARI_MAC = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15".freeze
  CHROME_WINDOWS = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36".freeze
  SAFARI_IPHONE = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1".freeze

  test "a browser version change does not change the fingerprint" do
    assert_equal DeviceFingerprint.for(CHROME_MAC_140), DeviceFingerprint.for(CHROME_MAC_141)
  end

  test "a browser family change changes the fingerprint" do
    assert_not_equal DeviceFingerprint.for(CHROME_MAC_141), DeviceFingerprint.for(SAFARI_MAC)
  end

  test "a platform change changes the fingerprint" do
    assert_not_equal DeviceFingerprint.for(CHROME_MAC_141), DeviceFingerprint.for(CHROME_WINDOWS)
  end

  test "produces a lowercase browser and platform pair" do
    assert_equal "chrome|macintosh", DeviceFingerprint.for(CHROME_MAC_141)
    assert_equal "safari|iphone", DeviceFingerprint.for(SAFARI_IPHONE)
  end

  test "returns nil for blank input" do
    assert_nil DeviceFingerprint.for(nil)
    assert_nil DeviceFingerprint.for("")
    assert_nil DeviceFingerprint.for("   ")
  end

  # UserAgent.parse does not raise and does not return nil for junk; it echoes
  # the input back as the browser name. The contract here is only that a
  # malformed header cannot produce a 500 on every request.
  test "does not raise on junk input" do
    assert_nothing_raised do
      DeviceFingerprint.for("garbage-string")
      DeviceFingerprint.for("<script>alert(1)</script>")
      DeviceFingerprint.for("\x00\xff invalid bytes")
    end
  end
end
