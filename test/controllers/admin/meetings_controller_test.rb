require "test_helper"

module Admin
  class MeetingsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "meeting-admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      @committee = Committee.create!(name: "Plan Commission")
      @meeting = Meeting.create!(
        body_name: "Plan Commission Meeting",
        meeting_type: "Regular",
        starts_at: Time.zone.local(2026, 6, 14, 18, 30),
        status: "minutes_posted",
        detail_page_url: "https://example.com/meetings/plan-commission-2026-06-14",
        committee: @committee
      )
    end

    test "requires admin authentication" do
      get admin_meeting_url(@meeting)

      assert_redirected_to new_session_path
    end

    test "index requires admin authentication" do
      get admin_meetings_url

      assert_redirected_to new_session_path
    end

    test "admin can list meetings and reach image management" do
      Meeting.create!(
        body_name: "Undated Meeting",
        meeting_type: "Regular",
        status: "scheduled",
        detail_page_url: "https://example.com/meetings/undated"
      )
      @meeting.generated_images.create!(
        status: "ready",
        purpose: GeneratedImages::Generator::DEFAULT_PURPOSE,
        generated_at: Time.current,
        source_generation_tier: "test"
      )
      sign_in_as_admin

      get admin_meetings_url

      assert_response :success
      assert_select "h1", text: "Meetings"
      assert_select "tbody tr:first-child" do
        assert_select "td", text: "Plan Commission"
        assert_select "td", text: "Plan Commission"
      end
      assert_select ".badge", text: "ready"
      assert_select "a[href=?]", admin_meeting_path(@meeting), text: "Manage image"
    end

    test "admin dashboard links to meetings" do
      sign_in_as_admin

      get admin_root_url

      assert_response :success
      assert_select ".card ul a[href=?]", admin_meetings_path, text: "Meetings"
    end

    test "admin can view meeting image management page" do
      sign_in_as_admin

      get admin_meeting_url(@meeting)

      assert_response :success
      assert_select "h1", text: "Plan Commission"
      assert_select "h2", text: "Meeting details"
      assert_select "dd", text: "Plan Commission"
      assert_select "dd", text: "Regular"
      assert_select "a[href=?]", meeting_path(@meeting), text: "View public meeting"
    end

    test "admin meeting page renders generated image controls" do
      sign_in_as_admin

      get admin_meeting_url(@meeting)

      assert_response :success
      assert_select "h3", text: "Meeting image"
      assert_select "form[action=?][method=post]", regenerate_generated_images_path do
        assert_select "input[name=imageable_type][value=Meeting]", 1
        assert_select "input[name=imageable_id][value=?]", @meeting.id.to_s, 1
        assert_select "textarea[name=custom_prompt]", 1
        assert_select "input[type=submit][value='Queue image']", 1
      end
      assert_select "form[action=?][method=post][enctype='multipart/form-data']", generated_images_path do
        assert_select "label", text: "Upload replacement"
        assert_select "input[type=file][name='generated_image[file]']", 1
        assert_select "input[type=submit][value='Save upload']", 1
      end
    end

    private

      def sign_in_as_admin
        post session_url, params: { email_address: @admin.email_address, password: "password" }
        follow_redirect!

        totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
        post mfa_session_url, params: { code: totp.now }
        follow_redirect!
      end
  end
end
