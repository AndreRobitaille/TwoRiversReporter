class TransactionalEmail
  class MissingTransactionalId < StandardError; end

  # Every Loops template this app can send. Each reader raises
  # MissingTransactionalId in production when its env var is unset.
  TRANSACTIONAL_ID_READERS = %i[
    magic_link_transactional_id
    application_link_transactional_id
    admin_application_notification_transactional_id
    no_account_transactional_id
    application_pending_transactional_id
  ].freeze

  # Called from an initializer so a production container refuses to boot when a
  # transactional id is missing. Nothing rescues MissingTransactionalId at
  # request time, so an unset id would otherwise surface as a 500 on the exact
  # sign-in branches that must stay indistinguishable — a missing id for the
  # no-account template would turn "unknown address" into a 500 and "known
  # address" into a 302, which is a perfect address-enumeration oracle.
  def self.verify_transactional_ids!
    return true unless Rails.env.production?

    TRANSACTIONAL_ID_READERS.each { |reader| public_send(reader) }
    true
  end

  Message = Struct.new(:email, :transactional_id, :data_variables, keyword_init: true) do
    def initialize(**kwargs)
      super
      self.data_variables = deep_freeze(data_variables.deep_dup) if data_variables
      freeze
    end

    def deliver_now
      return true unless Rails.env.production?

      LoopsDelivery.deliver_now(email: email, transactional_id: transactional_id, data_variables: data_variables)
    end

    private

    def deep_freeze(value)
      case value
      when Hash
        value.each_value { |nested_value| deep_freeze(nested_value) }
      when Array
        value.each { |nested_value| deep_freeze(nested_value) }
      end

      value.freeze
    end
  end

  # Every URL below is absolute. A Loops template drops these straight into an
  # `<a href>` in an email client, where there is no page to resolve a bare path
  # against — "/session/magic_link?token=..." is simply not clickable, and the
  # magic link is the only way anyone signs in. The host comes from
  # config.action_mailer.default_url_options (config/environments/*.rb), so no
  # environment's domain is written down here.
  def self.magic_link(user, magic_link)
    transactional_id = magic_link_transactional_id
    Message.new(
      email: user.email_address,
      transactional_id: transactional_id,
      data_variables: {
        sign_in_url: sign_in_url(magic_link)
      }
    )
  end

  def self.application_link(user, membership_application, magic_link)
    transactional_id = application_link_transactional_id
    Message.new(
      email: user.email_address,
      transactional_id: transactional_id,
      data_variables: {
        application_url: url_helpers.edit_application_url(membership_application, token: magic_link.raw_token, **url_options)
      }
    )
  end

  def self.application_approved(user, membership_application, magic_link)
    Message.new(
      email: user.email_address,
      transactional_id: magic_link_transactional_id,
      data_variables: {
        sign_in_url: sign_in_url(magic_link)
      }
    )
  end

  def self.admin_application_notifications(applications)
    email = if Rails.env.production?
      ENV.fetch("ADMIN_NOTIFICATION_EMAIL") { raise MissingTransactionalId, "ADMIN_NOTIFICATION_EMAIL is required in production" }
    else
      ENV["ADMIN_NOTIFICATION_EMAIL"].presence || "admin@example.com"
    end

    Message.new(
      email: email,
      transactional_id: admin_application_notification_transactional_id,
      data_variables: {
        application_count: applications.size,
        applicant_emails: applications.map { |application| application.user.email_address }
      }
    )
  end

  def self.no_account(email_address)
    Message.new(
      email: email_address,
      transactional_id: no_account_transactional_id,
      data_variables: {
        apply_url: url_helpers.new_application_url(**url_options)
      }
    )
  end

  def self.application_pending(user)
    Message.new(
      email: user.email_address,
      transactional_id: application_pending_transactional_id,
      data_variables: {}
    )
  end

  # The token is appended by hand instead of being passed to the route helper so
  # the CGI.escape below stays exactly as it was. A token mangled in transit does
  # not match a stored digest, and the sign-in fails with nothing to look at.
  def self.sign_in_url(magic_link)
    "#{url_helpers.magic_link_public_session_url(**url_options)}?token=#{CGI.escape(magic_link.raw_token)}"
  end
  private_class_method :sign_in_url

  def self.url_helpers
    Rails.application.routes.url_helpers
  end
  private_class_method :url_helpers

  # The one host configured per environment. Handed to each helper explicitly
  # rather than assigned to Rails.application.routes.default_url_options: route
  # set defaults outrank the request's own host at request time, so setting them
  # globally rewrites every redirect the app issues to this host — which, among
  # other things, drops the session cookie on any other hostname the app answers
  # on.
  def self.url_options
    Rails.application.config.action_mailer.default_url_options
  end
  private_class_method :url_options

  def self.admin_application_notification_transactional_id
    ENV["LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID"].presence || default_admin_application_notification_transactional_id
  end

  def self.no_account_transactional_id
    ENV["LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID"].presence || default_no_account_transactional_id
  end

  def self.application_pending_transactional_id
    ENV["LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID"].presence || default_application_pending_transactional_id
  end

  def self.default_no_account_transactional_id
    return "no_account" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID is required in production"
  end

  def self.default_application_pending_transactional_id
    return "application_pending" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID is required in production"
  end

  def self.magic_link_transactional_id
    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"].presence || default_magic_link_transactional_id
  end

  def self.application_link_transactional_id
    ENV["LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID"].presence || default_application_link_transactional_id
  end

  def self.default_magic_link_transactional_id
    return "sign_in_magic_link" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_MAGIC_LINK_TRANSACTIONAL_ID is required in production"
  end

  def self.default_application_link_transactional_id
    return "application_magic_link" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_APPLICATION_LINK_TRANSACTIONAL_ID is required in production"
  end

  def self.default_admin_application_notification_transactional_id
    return "admin_application_notifications" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID is required in production"
  end
end
