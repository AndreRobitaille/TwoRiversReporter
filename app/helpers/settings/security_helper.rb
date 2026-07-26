module Settings::SecurityHelper
  # DeviceFingerprint is deliberately machine-shaped ("chrome|macintosh") — see
  # the model for why. This is the one place a member actually reads it, so it
  # exists purely to translate that string back into something a non-technical
  # reader can parse without exposing the raw pair as-is.
  KNOWN_PLATFORM_NAMES = {
    "macintosh" => "Mac",
    "windows" => "Windows",
    "linux" => "Linux",
    "x11" => "Linux",
    "iphone" => "iPhone",
    "ipad" => "iPad",
    "android" => "Android",
    "chromeos" => "Chromebook"
  }.freeze

  def describe_known_context_device(fingerprint)
    return "Unknown browser" if fingerprint.blank?

    browser, platform = fingerprint.split("|", 2)
    browser_name = browser.presence&.capitalize || "Unknown browser"
    return browser_name if platform.blank?

    platform_name = KNOWN_PLATFORM_NAMES.fetch(platform, platform.capitalize)
    "#{browser_name} on #{platform_name}"
  end
end
