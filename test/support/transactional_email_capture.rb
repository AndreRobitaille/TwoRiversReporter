# Captures the actual immutable message, including its recipient and usable URL.
# Only the final transport is replaced; token creation and consumption stay real.
module TransactionalEmailCapture
  def capture_transactional_emails
    messages = []
    original_delivery = TransactionalEmail::Message.instance_method(:deliver_now)
    TransactionalEmail::Message.define_method(:deliver_now) do
      messages << self
      true
    end

    yield messages
  ensure
    TransactionalEmail::Message.define_method(:deliver_now, original_delivery)
  end
end
