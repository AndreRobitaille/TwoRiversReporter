class TransactionalEmail
  class MissingTransactionalId < StandardError; end

  Message = Struct.new(:email, :transactional_id, :data_variables, keyword_init: true) do
    def initialize(**kwargs)
      super
      freeze
    end

    def deliver_now
      return true unless Rails.env.production?

      LoopsDelivery.deliver_now(email: email, transactional_id: transactional_id, data_variables: data_variables)
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

  def self.magic_link_transactional_id
    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"].presence || default_magic_link_transactional_id
  end

  def self.default_magic_link_transactional_id
    return "sign_in_magic_link" unless Rails.env.production?

    raise MissingTransactionalId, "LOOPS_MAGIC_LINK_TRANSACTIONAL_ID is required in production"
  end
end
