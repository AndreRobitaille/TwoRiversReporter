class MembershipApplication < ApplicationRecord
  STATUSES = %w[email_pending submitted approved rejected].freeze

  belongs_to :user
  belongs_to :reviewed_by, class_name: "User", optional: true

  validates :status, inclusion: { in: STATUSES }
  validates :first_name, :last_name, :city, :state, presence: true, unless: :email_pending?
  validate :facebook_profile_url_is_secure_facebook_url, if: :facebook_profile_url_changed?

  # Street joined the required set in July 2026. Applications submitted before
  # then have none on file, and a blanket presence check would make those rows
  # permanently invalid — every later save would fail, including the admin
  # approving or rejecting them, which is the one thing still owed to those
  # applicants. So require it where it can actually be supplied: on the
  # applicant's own submission, and on any later save that touches the field.
  # A pre-existing row that nobody edits stays saveable; nothing new gets in
  # without a street.
  validates :street, presence: true, if: :street_required?

  def email_pending?
    status == "email_pending"
  end

  private

    def facebook_profile_url_is_secure_facebook_url
      return if facebook_profile_url.blank?

      uri = URI.parse(facebook_profile_url)
      host = uri.host.to_s.downcase
      return if uri.scheme&.casecmp?("https") && (host == "facebook.com" || host.end_with?(".facebook.com"))

      errors.add(:facebook_profile_url, "must be a secure Facebook URL")
    rescue URI::InvalidURIError
      errors.add(:facebook_profile_url, "must be a secure Facebook URL")
    end

    def street_required?
      return false if email_pending?

      street_changed? || status_changed?(from: "email_pending")
    end
end
