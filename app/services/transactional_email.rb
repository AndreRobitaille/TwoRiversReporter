class TransactionalEmail
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
    Message.new(
      email: user.email_address,
      transactional_id: "sign_in_magic_link",
      data_variables: {
        sign_in_url: "/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}",
        raw_token: magic_link.raw_token
      }
    )
  end
end
