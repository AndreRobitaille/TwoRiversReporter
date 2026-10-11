require "test_helper"
require "action_dispatch/system_test_case"
require_relative "support/transactional_email_capture"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  include TransactionalEmailCapture

  driven_by :selenium, using: :headless_chrome, screen_size: [ 1280, 900 ] do |options|
    options.binary = ENV["CHROME_BIN"] if ENV["CHROME_BIN"].present?
    options.add_argument("--disable-dev-shm-usage")
  end

  Capybara.server_host = "0.0.0.0"
  Capybara.app_host = "http://localhost"

  setup do
    @original_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    @original_email_url_options = Rails.application.config.action_mailer.default_url_options

    visit root_path
    Rails.application.config.action_mailer.default_url_options = {
      protocol: "http", host: "localhost", port: Capybara.current_session.server.port
    }
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original_forgery_protection
    Rails.application.config.action_mailer.default_url_options = @original_email_url_options
  end

  private

    def sign_in_by_email(user)
      visit settings_profile_path
      assert_current_path new_public_session_path
      assert_no_selector "a[href='#{public_session_path}'][data-turbo-method='delete']"

      capture_transactional_emails do |messages|
        fill_in "Email address", with: user.email_address
        click_button "Send magic link"
        assert_text "Check your email"

        message = messages.sole
        assert_equal user.email_address, message.email
        link = user.magic_links.sole
        url = URI.parse(message.data_variables.fetch(:sign_in_url))
        assert_equal "localhost", url.host
        assert_equal Capybara.current_session.server.port, url.port

        visit url.to_s
        assert_button "Continue to my account"
        assert_predicate link.reload, :unused?
        assert_empty user.sessions
        assert_nil authentication_cookie

        click_button "Continue to my account"
        assert_current_path settings_profile_path
        assert_text user.email_address
        assert_not_nil link.reload.used_at
        assert_equal user.id, user.sessions.sole.user_id
      end
    end

    def authentication_cookie
      page.driver.browser.manage.all_cookies.find { |cookie| cookie[:name] == "session_id" }
    end
end
