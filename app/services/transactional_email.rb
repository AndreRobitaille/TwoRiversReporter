class TransactionalEmail
  class MissingTransactionalId < StandardError; end

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

  def self.magic_link(user, magic_link)
    transactional_id = magic_link_transactional_id
    Message.new(
      email: user.email_address,
      transactional_id: transactional_id,
      data_variables: {
        sign_in_url: "/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}"
      }
    )
  end

  def self.application_link(user, membership_application, magic_link)
    transactional_id = application_link_transactional_id
    Message.new(
      email: user.email_address,
      transactional_id: transactional_id,
      data_variables: {
        application_url: Rails.application.routes.url_helpers.edit_application_path(membership_application, token: magic_link.raw_token)
      }
    )
  end

  def self.application_approved(user, membership_application, magic_link)
    Message.new(
      email: user.email_address,
      transactional_id: magic_link_transactional_id,
      data_variables: {
        sign_in_url: "/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}"
      }
    )
  end

  def self.admin_application_notifications(applications)
    Message.new(
      email: ENV.fetch("ADMIN_NOTIFICATION_EMAIL", "admin@example.com"),
      transactional_id: ENV["LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID"].presence || "admin_application_notifications",
      data_variables: {
        application_count: applications.size,
        applicant_emails: applications.map { |application| application.user.email_address }
      }
    )
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
end
