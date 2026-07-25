require "test_helper"

class TransactionalEmailTest < ActiveSupport::TestCase
  test "magic_link builds an immutable message with a configured transactional id and no raw token data" do
    user = User.create!(email_address: "active@example.com", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"] = "sign_in_magic_link_test"

    message = TransactionalEmail.magic_link(user, magic_link)

    assert_equal user.email_address, message.email
    assert_equal "sign_in_magic_link_test", message.transactional_id
    assert_not_includes message.data_variables.keys, :raw_token
    # Absolute, not a bare path: an email client has no page to resolve
    # "/session/magic_link?token=..." against, so a path here is a dead link on
    # the one route anybody signs in through.
    assert_equal "http://example.com/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}",
      message.data_variables[:sign_in_url]
    assert_predicate message, :frozen?

    assert_raises(FrozenError) { message.data_variables[:sign_in_url] = "/tampered" }
    assert_raises(FrozenError) { message.data_variables[:new_key] = "value" }
    assert_raises(FrozenError) { message.data_variables[:sign_in_url] << "&tampered=1" }
    assert_equal "http://example.com/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}",
      message.data_variables[:sign_in_url]
  ensure
    ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")
  end

  test "application_approved sends a sign in compatible link and keeps the token memory only" do
    user = User.create!(email_address: "applicant@example.com", status: "active")
    application = user.membership_applications.create!(status: "approved", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    message = TransactionalEmail.application_approved(user, application, magic_link)

    assert_equal user.email_address, message.email
    assert_equal TransactionalEmail.send(:magic_link_transactional_id), message.transactional_id
    assert_equal "http://example.com/session/magic_link?token=#{CGI.escape(magic_link.raw_token)}",
      message.data_variables[:sign_in_url]
    assert_not_includes message.data_variables.keys, :application_url
  end

  test "application_link carries an absolute edit url with the token intact" do
    user = User.create!(email_address: "applicant@example.com", status: "pending", disabled_at: Time.current)
    application = user.membership_applications.create!(status: "email_pending", first_name: "Jane", last_name: "Member", city: "Two Rivers", state: "WI")
    magic_link = MagicLink.create_for!(user, purpose: "application")

    message = TransactionalEmail.application_link(user, application, magic_link)

    assert_equal "http://example.com/applications/#{application.to_param}/edit?token=#{CGI.escape(magic_link.raw_token)}",
      message.data_variables[:application_url]
  end

  test "deliver_now in test does not hit loops and succeeds through the fake path" do
    user = User.create!(email_address: "active@example.com", status: "active")
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
    user = User.create!(email_address: "active@example.com", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")
    before_jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.size

    ENV["LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"] = "sign_in_magic_link_test"

    TransactionalEmail.magic_link(user, magic_link).deliver_now

    assert_equal before_jobs, ActiveJob::Base.queue_adapter.enqueued_jobs.size
  ensure
    ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")
  end

  test "production missing transactional id raises" do
    user = User.create!(email_address: "active@example.com", status: "active")
    magic_link = MagicLink.create_for!(user, purpose: "sign_in")

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ENV.delete("LOOPS_MAGIC_LINK_TRANSACTIONAL_ID")

      assert_raises(TransactionalEmail::MissingTransactionalId) do
        TransactionalEmail.magic_link(user, magic_link)
      end
    end
  end

  test "production missing admin notification email raises instead of using a placeholder" do
    user = User.create!(email_address: "applicant@example.com", status: "active")
    application = user.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ENV.delete("ADMIN_NOTIFICATION_EMAIL")

      assert_raises(TransactionalEmail::MissingTransactionalId) do
        TransactionalEmail.admin_application_notifications([ application ])
      end
    end
  end

  test "production missing admin notification transactional id raises instead of using a placeholder" do
    user = User.create!(email_address: "applicant@example.com", status: "active")
    application = user.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ENV.delete("LOOPS_ADMIN_APPLICATION_NOTIFICATION_TRANSACTIONAL_ID")
      ENV["ADMIN_NOTIFICATION_EMAIL"] = "admin@example.com"

      assert_raises(TransactionalEmail::MissingTransactionalId) do
        TransactionalEmail.admin_application_notifications([ application ])
      end
    end
  ensure
    ENV.delete("ADMIN_NOTIFICATION_EMAIL")
  end

  test "no_account addresses the typed email and carries an apply url" do
    message = TransactionalEmail.no_account("stranger@example.com")

    assert_equal "stranger@example.com", message.email
    assert_equal "no_account", message.transactional_id
    assert_equal "http://example.com/applications/new", message.data_variables[:apply_url]
  end

  test "application_pending addresses the applicant" do
    user = User.create!(email_address: "waiting@example.com", status: "pending", disabled_at: Time.current)

    message = TransactionalEmail.application_pending(user)

    assert_equal "waiting@example.com", message.email
    assert_equal "application_pending", message.transactional_id
  end

  test "production missing no_account transactional id raises instead of using a placeholder" do
    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ENV.delete("LOOPS_NO_ACCOUNT_TRANSACTIONAL_ID")

      assert_raises(TransactionalEmail::MissingTransactionalId) do
        TransactionalEmail.no_account("stranger@example.com")
      end
    end
  end

  test "production missing application_pending transactional id raises instead of using a placeholder" do
    user = User.create!(email_address: "waiting@example.com", status: "pending", disabled_at: Time.current)

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      ENV.delete("LOOPS_APPLICATION_PENDING_TRANSACTIONAL_ID")

      assert_raises(TransactionalEmail::MissingTransactionalId) do
        TransactionalEmail.application_pending(user)
      end
    end
  end

  test "verify_transactional_ids! is a no-op outside production" do
    TransactionalEmail::TRANSACTIONAL_ID_READERS.each { |reader| ENV.delete(env_var_for(reader)) }

    assert TransactionalEmail.verify_transactional_ids!
  end

  test "verify_transactional_ids! passes in production when every id is set" do
    TransactionalEmail::TRANSACTIONAL_ID_READERS.each { |reader| ENV[env_var_for(reader)] = "set-#{reader}" }

    Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
      assert TransactionalEmail.verify_transactional_ids!
    end
  ensure
    TransactionalEmail::TRANSACTIONAL_ID_READERS.each { |reader| ENV.delete(env_var_for(reader)) }
  end

  test "verify_transactional_ids! raises in production for each missing id in turn" do
    readers = TransactionalEmail::TRANSACTIONAL_ID_READERS
    assert_equal 5, readers.size, "every Loops template must be covered by the boot guard"

    readers.each do |missing|
      readers.each { |reader| ENV[env_var_for(reader)] = "set-#{reader}" }
      ENV.delete(env_var_for(missing))

      Rails.stub(:env, ActiveSupport::StringInquirer.new("production")) do
        error = assert_raises(TransactionalEmail::MissingTransactionalId, "#{missing} is not covered by the boot guard") do
          TransactionalEmail.verify_transactional_ids!
        end

        assert_match env_var_for(missing), error.message
      end
    end
  ensure
    TransactionalEmail::TRANSACTIONAL_ID_READERS.each { |reader| ENV.delete(env_var_for(reader)) }
  end

  test "every url handed to Loops is absolute, across every builder" do
    urls_checked = 0

    message_builders.each do |builder, build_message|
      build_message.call.data_variables.each do |key, value|
        Array(value).each do |entry|
          next unless entry.is_a?(String)

          if key.to_s.end_with?("_url")
            urls_checked += 1
            assert_match(%r{\Ahttps?://[^/]+/}, entry,
              "#{builder} sends #{key} as #{entry.inspect} — a Loops template drops this into an <a href>, where a bare path is a dead link")
          else
            assert_no_match(%r{\A/}, entry,
              "#{builder} sends #{key} as #{entry.inspect}, which looks like a bare path")
          end
        end
      end
    end

    assert_operator urls_checked, :>=, 4, "the sweep found no URLs to check — message_builders is probably not building anything"
  end

  test "the absolute url sweep names every builder TransactionalEmail exposes" do
    # A new builder that mails a bare path fails the sweep above without anyone
    # remembering to add an assertion for it — but only if the sweep can see it,
    # so a builder missing from message_builders fails here first.
    exposed = TransactionalEmail.methods(false).map(&:to_s)
      .reject { |name| name.end_with?("_transactional_id") || name == "verify_transactional_ids!" }

    assert_equal exposed.sort, message_builders.keys.map(&:to_s).sort
  end

  private

    # :magic_link_transactional_id => "LOOPS_MAGIC_LINK_TRANSACTIONAL_ID"
    def env_var_for(reader)
      "LOOPS_#{reader.to_s.upcase}"
    end

    # One invocation per public builder, keyed by method name so the coverage
    # test can compare this list against what the class actually exposes.
    def message_builders
      user = User.create!(email_address: "sweep@example.com", status: "active")
      application = user.membership_applications.create!(status: "submitted", first_name: "Jane", last_name: "Member", street: "123 Main St", city: "Two Rivers", state: "WI")
      magic_link = MagicLink.create_for!(user, purpose: "sign_in")

      {
        magic_link: -> { TransactionalEmail.magic_link(user, magic_link) },
        application_link: -> { TransactionalEmail.application_link(user, application, magic_link) },
        application_approved: -> { TransactionalEmail.application_approved(user, application, magic_link) },
        admin_application_notifications: -> { TransactionalEmail.admin_application_notifications([ application ]) },
        no_account: -> { TransactionalEmail.no_account("stranger@example.com") },
        application_pending: -> { TransactionalEmail.application_pending(user) }
      }
    end
end
