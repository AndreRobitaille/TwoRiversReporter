require "test_helper"
require_relative "../support/council_service_sources"

class CouncilServicePeriodTest < ActiveSupport::TestCase
  include CouncilServiceSources

  setup do
    @member = Member.create!(name: "Jordan Service")
    @source = service_source
    @attributes = { member: @member, period_key: "2024-election", started_on: "2024-04-16",
      start_source_version: @source, start_page: 5 }
  end

  test "dates require retained sources and explicit pages without guessing an end" do
    period = CouncilServicePeriod.create!(@attributes)
    assert_nil period.ended_on
    assert_not period.update(started_on: nil)
    assert_not period.update(@attributes.merge(start_page: 0))
    assert_not period.update(@attributes.merge(start_source_version: nil))

    period.reload
    assert_not period.update(ended_on: "2025-04-15")
    assert_not period.update(end_source_version: @source, end_page: 0)
    assert_not period.update(ended_on: "2024-04-15", end_page: 2)
    assert period.update(ended_on: "2025-04-15", end_page: 2)
  end

  test "a failed shared-source batch does not partially publish members or create identities" do
    other = Member.create!(name: "Taylor Service")
    entries = [ { member_id: @member.id, started_on: "2024-04-16" }, { member_id: other.id, started_on: nil } ]
    assert_no_difference [ "CouncilServicePeriod.count", "Member.count" ] do
      assert_raises ActiveRecord::RecordInvalid do
        CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: @source, page: 5, entries: entries)
      end
    end
  end

  test "member merge preserves service histories and rolls back conflicting period keys" do
    period = CouncilServicePeriod.create!(@attributes)
    target = Member.create!(name: "Jordan Canonical")
    @member.merge_into!(target)
    assert_equal target.id, period.reload.member_id
    assert_equal @source.id, period.start_source_version_id

    duplicate = Member.create!(name: "Jordan Duplicate")
    conflicting = CouncilServicePeriod.create!(@attributes.merge(member: duplicate, started_on: "2024-04-17"))
    error = assert_raises ArgumentError do
      duplicate.merge_into!(target)
    end
    assert_match "Council service dates could not be merged", error.message
    assert_equal duplicate.id, conflicting.reload.member_id
    assert Member.exists?(duplicate.id)
    assert_equal Date.new(2024, 4, 16), period.reload.started_on
  end
end
