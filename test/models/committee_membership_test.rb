require "test_helper"

class CommitteeMembershipTest < ActiveSupport::TestCase
  setup do
    @committee = Committee.create!(name: "City Council")
    @member = Member.create!(name: "Jane Doe")
  end

  test "valid membership saves" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, role: "member")
    assert membership.save
  end

  test "committee is required" do
    membership = CommitteeMembership.new(member: @member)
    assert_not membership.valid?
  end

  test "member is required" do
    membership = CommitteeMembership.new(committee: @committee)
    assert_not membership.valid?
  end

  test "role validates inclusion when present" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, role: "dictator")
    assert_not membership.valid?
  end

  test "role can be nil" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, role: nil)
    assert membership.valid?
  end

  test "source defaults to admin_manual" do
    membership = CommitteeMembership.create!(committee: @committee, member: @member)
    assert_equal "admin_manual", membership.source
  end

  test "source validates inclusion" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, source: "magic")
    assert_not membership.valid?
  end

  test "current scope returns memberships without end date" do
    current = CommitteeMembership.create!(committee: @committee, member: @member)
    ended = CommitteeMembership.create!(
      committee: @committee,
      member: Member.create!(name: "Past Member"),
      ended_on: 1.month.ago
    )

    assert_includes CommitteeMembership.current, current
    assert_not_includes CommitteeMembership.current, ended
  end

  test "member has committees through memberships" do
    CommitteeMembership.create!(committee: @committee, member: @member)
    assert_includes @member.committees, @committee
  end
end
