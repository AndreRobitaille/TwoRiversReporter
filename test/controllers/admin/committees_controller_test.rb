require "test_helper"

class Admin::CommitteesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "committee-admin@test.com", password: "password", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!

    post session_url, params: { email_address: "committee-admin@test.com", password: "password" }
    follow_redirect!

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect!

    @committee = Committee.create!(
      name: "Plan Commission",
      description: "Zoning and planning",
      committee_type: "city",
      status: "active"
    )
  end

  test "index lists committees" do
    get admin_committees_url
    assert_response :success
    assert_select "a", text: "Plan Commission"
  end

  test "show displays committee details" do
    get admin_committee_url(@committee)
    assert_response :success
  end

  test "new renders form" do
    get new_admin_committee_url
    assert_response :success
  end

  test "create saves valid committee" do
    assert_difference "Committee.count", 1 do
      post admin_committees_url, params: {
        committee: { name: "New Board", description: "Does stuff", committee_type: "city", status: "active" }
      }
    end
    assert_redirected_to admin_committee_url(Committee.find_by(name: "New Board"))
  end

  test "create rejects invalid committee" do
    assert_no_difference "Committee.count" do
      post admin_committees_url, params: {
        committee: { name: "", description: "No name" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update modifies committee" do
    patch admin_committee_url(@committee), params: {
      committee: { description: "Updated description" }
    }
    assert_redirected_to admin_committee_url(@committee)
    assert_equal "Updated description", @committee.reload.description
  end

  test "destroy deletes committee" do
    assert_difference "Committee.count", -1 do
      delete admin_committee_url(@committee)
    end
    assert_redirected_to admin_committees_url
  end

  test "create_alias adds alias" do
    assert_difference "CommitteeAlias.count", 1 do
      post create_alias_admin_committee_url(@committee), params: { name: "PC" }
    end
    assert_redirected_to admin_committee_url(@committee)
  end

  test "destroy_alias removes alias" do
    alias_record = CommitteeAlias.create!(committee: @committee, name: "PC")
    assert_difference "CommitteeAlias.count", -1 do
      delete destroy_alias_admin_committee_url(@committee, alias_id: alias_record.id)
    end
    assert_redirected_to admin_committee_url(@committee)
  end
end
