require "test_helper"

class CanonicalRosters::SynchronizerTest < ActiveSupport::TestCase
  setup do
    @council = Committee.create!(name: "City Council")
    @verified_at = Time.zone.parse("2026-09-03 10:00")
  end

  test "official roster replaces an AI role and creates the durable office" do
    mark = Member.create!(name: "Mark Bittner")
    membership = CommitteeMembership.create!(
      committee: @council, member: mark, role: "staff", source: "ai_extracted"
    )

    result = synchronize(snapshot(entries: [ council_entry("Mark Bittner") ]))

    assert_equal "member", membership.reload.role
    assert_equal "official_roster", membership.source
    assert_equal "City Council Member", mark.reload.current_position_title
    assert_equal %w[membership_updated position_created], result.changes.map(&:action)
  end

  test "preserves manually managed memberships" do
    mark = Member.create!(name: "Mark Bittner")
    membership = CommitteeMembership.create!(
      committee: @council, member: mark, role: "chair", source: "admin_manual"
    )

    synchronize(snapshot(entries: [ council_entry("Mark Bittner") ]))

    assert_equal "chair", membership.reload.role
    assert_equal "admin_manual", membership.source
    assert_equal "City Council Member", mark.reload.current_position_title
  end

  test "ends non-manual memberships omitted by the canonical roster" do
    former = Member.create!(name: "Former Member")
    membership = CommitteeMembership.create!(
      committee: @council, member: former, role: "member", source: "ai_extracted"
    )

    synchronize(snapshot(entries: [ council_entry("Mark Bittner") ]))

    assert_equal Date.current, membership.reload.ended_on
  end

  test "dry run reports changes and rolls them back" do
    result = synchronize(snapshot(entries: [ council_entry("Mark Bittner") ]), dry_run: true)

    assert result.changed?
    assert_not Member.exists?(name: "Mark Bittner")
    assert_equal 0, MemberPosition.count
  end

  test "verification refresh is not reported as a semantic change" do
    roster = snapshot(entries: [ council_entry("Mark Bittner") ])
    synchronize(roster)

    result = CanonicalRosters::Synchronizer.new(
      snapshots: [ roster ], dry_run: false, verified_at: @verified_at + 1.hour
    ).call

    assert_not result.changed?
    assert_equal @verified_at + 1.hour, Member.find_by!(name: "Mark Bittner").member_positions.current.pick(:verified_at)
  end

  private

  def synchronize(roster, dry_run: false)
    CanonicalRosters::Synchronizer.new(
      snapshots: [ roster ], dry_run: dry_run, verified_at: @verified_at
    ).call
  end

  def snapshot(entries:)
    CanonicalRosters::Snapshot.new(
      key: "city_council",
      committee_name: "City Council",
      membership_source: "official_roster",
      position_source: "official_website",
      source_url: "https://example.com/council",
      managed_roles: %w[chair vice_chair member secretary alternate],
      entries: entries
    )
  end

  def council_entry(name)
    CanonicalRosters::Entry.new(
      name: name,
      source_name: name,
      membership_role: "member",
      membership_title: "City Council Member",
      position_kind: "city_council",
      position_title: "City Council Member"
    )
  end
end
