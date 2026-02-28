require "test_helper"

class Admin::MembersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "member-admin@test.com", password: "password", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!

    post session_url, params: { email_address: "member-admin@test.com", password: "password" }
    follow_redirect!

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect!

    @member = Member.create!(name: "Jane Doe")
  end

  test "index lists members" do
    get admin_members_url
    assert_response :success
    assert_select "a", text: "Jane Doe"
  end

  test "show displays member details" do
    get admin_member_url(@member)
    assert_response :success
    assert_select "h1", text: "Jane Doe"
  end

  test "create_alias adds alias" do
    assert_difference "MemberAlias.count", 1 do
      post create_alias_admin_member_url(@member), params: { name: "J. Doe" }
    end
    assert_redirected_to admin_member_url(@member)
  end

  test "destroy_alias removes alias" do
    alias_record = MemberAlias.create!(member: @member, name: "J. Doe")
    assert_difference "MemberAlias.count", -1 do
      delete destroy_alias_admin_member_url(@member, alias_id: alias_record.id)
    end
    assert_redirected_to admin_member_url(@member)
  end

  test "merge reassigns records and destroys source" do
    target = Member.create!(name: "Janet Doe")
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-merge-test", starts_at: 1.day.ago)
    motion = Motion.create!(meeting: meeting, description: "Approve budget", outcome: "passed")
    Vote.create!(member: @member, motion: motion, value: "yes")

    assert_difference "Member.count", -1 do
      post merge_admin_member_url(@member), params: { target_member_id: target.id }
    end
    assert_redirected_to admin_member_url(target)
    assert_equal target, Vote.find_by(motion: motion).member
  end

  test "merge rejects merging into self" do
    post merge_admin_member_url(@member), params: { target_member_id: @member.id }
    assert_redirected_to admin_member_url(@member)
    assert_equal "Cannot merge member into itself", flash[:alert]
  end
end
