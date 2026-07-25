module Admin::MembershipApplicationsHelper
  # Applicants type phone numbers every possible way and the column is
  # unvalidated free text, so this normalises for *display only* — the stored
  # string is never touched.
  #
  # A trailing extension is peeled off first ("x12", "ext. 12", "#12") so it
  # doesn't inflate the digit count, then reattached. A leading US country code
  # is dropped. Anything that is not a 10-digit North American number after that
  # — seven digits, an international number, a vanity number with letters,
  # outright junk — is returned exactly as it was stored. Showing an admin the
  # raw string is always more useful than showing them a mangled one.
  EXTENSION_PATTERN = /[\s,;.\-]*(?:x|ext\.?|extension|#)\s*(\d+)\s*\z/i

  def formatted_phone_number(value)
    raw = value.to_s
    return raw if raw.blank?

    trimmed = raw.strip
    extension = trimmed[EXTENSION_PATTERN, 1]
    digits = trimmed.sub(EXTENSION_PATTERN, "").gsub(/\D/, "")
    digits = digits[1..] if digits.length == 11 && digits.start_with?("1")

    return raw unless digits.length == 10

    formatted = "#{digits[0, 3]}-#{digits[3, 3]}-#{digits[6, 4]}"
    extension.present? ? "#{formatted} x#{extension}" : formatted
  end
end
