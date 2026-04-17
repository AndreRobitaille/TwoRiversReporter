require "test_helper"

class AgendaItemTest < ActiveSupport::TestCase
  test "substantive scope includes legacy rows and kind item rows but excludes section rows" do
    meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "minutes_posted",
      detail_page_url: "http://example.com/agenda-item-scope-test"
    )

    legacy_item = AgendaItem.create!(meeting: meeting, title: "Legacy Flat Item", order_index: 1)
    section = AgendaItem.create!(meeting: meeting, title: "NEW BUSINESS", order_index: 2, kind: "section")
    child = AgendaItem.create!(meeting: meeting, title: "Storm Water Grant", order_index: 3, kind: "item", parent: section)

    assert_includes AgendaItem.substantive, legacy_item
    assert_includes AgendaItem.substantive, child
    refute_includes AgendaItem.substantive, section
    assert_equal "NEW BUSINESS — Storm Water Grant", child.display_context_title
    assert_predicate legacy_item, :substantive?
    assert_predicate section, :structural?
  end

  test "parent must belong to the same meeting and cannot be self" do
    meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "minutes_posted",
      detail_page_url: "http://example.com/agenda-item-parent-test"
    )
    other_meeting = Meeting.create!(
      body_name: "Plan Commission",
      meeting_type: "Regular",
      starts_at: 1.day.from_now,
      status: "minutes_posted",
      detail_page_url: "http://example.com/agenda-item-parent-test-2"
    )

    section = AgendaItem.create!(meeting: meeting, title: "NEW BUSINESS", kind: "section", order_index: 1)
    other_section = AgendaItem.create!(meeting: other_meeting, title: "OLD BUSINESS", kind: "section", order_index: 1)
    child = AgendaItem.new(meeting: meeting, title: "Storm Water Grant", kind: "item", order_index: 2, parent: other_section)

    assert_not child.valid?
    assert_includes child.errors[:parent], "must belong to the same meeting"

    section.parent = section
    assert_not section.valid?
    assert_includes section.errors[:parent], "cannot be self"
  end

  test "parent cannot create cycles and unsaved parent is not treated as self" do
    meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "minutes_posted",
      detail_page_url: "http://example.com/agenda-item-cycle-test"
    )

    parent = AgendaItem.new(meeting: meeting, title: "Unsaved Section", kind: "section", order_index: 1)
    child = AgendaItem.new(meeting: meeting, title: "Unsaved Child", kind: "item", order_index: 2, parent: parent)
    assert child.valid?

    section = AgendaItem.create!(meeting: meeting, title: "NEW BUSINESS", kind: "section", order_index: 3)
    item = AgendaItem.create!(meeting: meeting, title: "Storm Water Grant", kind: "item", order_index: 4, parent: section)

    section.parent = item
    assert_not section.valid?
    assert_includes section.errors[:parent], "cannot create a cycle"
  end

  test "kind only allows supported values" do
    item = AgendaItem.new(kind: "other")

    assert_not item.valid?
    assert_includes item.errors[:kind], "is not included in the list"
  end
end
