require "test_helper"

class MeetingCommitteeTest < ActiveSupport::TestCase
  test "meeting can belong to a committee" do
    committee = Committee.create!(name: "City Council")
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/meeting/1",
      body_name: "City Council Meeting",
      committee: committee,
      starts_at: 1.day.ago
    )
    assert_equal committee, meeting.committee
  end

  test "meeting committee is optional" do
    meeting = Meeting.new(
      detail_page_url: "https://example.com/meeting/2",
      body_name: "Unknown Body",
      starts_at: 1.day.ago
    )
    assert meeting.valid?
    assert_nil meeting.committee
  end

  test "topic appearance gets committee_id from meeting via agenda_item_topic" do
    committee = Committee.create!(name: "Plan Commission")
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/meeting/3",
      body_name: "Plan Commission",
      committee: committee,
      starts_at: 1.day.ago
    )
    agenda_item = meeting.agenda_items.create!(title: "Test Item")
    topic = Topic.create!(name: "test topic", status: "approved")

    AgendaItemTopic.create!(agenda_item: agenda_item, topic: topic)

    appearance = TopicAppearance.last
    assert_equal committee, appearance.committee
    assert_equal "Plan Commission", appearance.body_name
  end
end
