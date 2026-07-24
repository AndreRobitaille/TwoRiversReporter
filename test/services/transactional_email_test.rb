require "test_helper"

class TransactionalEmailTest < ActiveSupport::TestCase
  test "magic_link builds an immutable message with a configured transactional id and no raw token data" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"] = "sign_in_magic_link_test"

    message = TransactionalEmail.magic_link(user, magic_link)

    assert_equal user.email_address, message.email
    assert_equal "sign_in_magic_link_test", message.transactional_id
    assert_not_includes message.data_variables.keys, :raw_token
    assert_includes message.data_variables[:sign_in_url], magic_link.raw_token
    assert_predicate message, :frozen?
  ensure
    ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")
  end

  test "deliver_now in test does not hit loops and succeeds through the fake path" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")
    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"] = "sign_in_magic_link_test"
    message = TransactionalEmail.magic_link(user, magic_link)

    LoopsDelivery.stub(:deliver_now, ->(**_) { flunk "expected fake path, not LoopsDelivery" }) do
      assert_equal true, message.deliver_now
    end
  ensure
    ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")
  end

  test "magic link send path does not enqueue an active job containing the raw token" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")
    before_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size

    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"] = "sign_in_magic_link_test"

    TransactionalEmail.magic_link(user, magic_link).deliver_now

    assert_equal before_jobs, ActiveJob::Base.queue_adapter.enqueued_jobs.size
  ensure
    ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")
  end

  test "production missing transactional id raises" do
    user = User.create!(email_address: "active@example.com", password: "password123", password_confirmation: "password123", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")

      assert_raises(TransactionalEmail::MissingTransactionalId) do
        TransactionalEmail.magic_link(user, magic_link)
      end
    end
  end
end
