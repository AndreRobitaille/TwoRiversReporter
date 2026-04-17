require "test_helper"

class Topics::RetrievalQueryBuilderTest < ActiveSupport::TestCase
  test "build_query excludes structural rows and keeps parent context" do
    topic = Topic.create!(name: "Downtown Parking", status: "approved")
    meeting = Meeting.create!(
      body_name: "City Council",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "agenda_posted",
      detail_page_url: "http://example.com/retrieval-query-test"
    )

    section = AgendaItem.create!(meeting: meeting, title: "NEW BUSINESS", kind: "section", order_index: 0)
    child = AgendaItem.create!(meeting: meeting, title: "Parking Ramp Expansion", kind: "item", parent: section, order_index: 1)
    legacy_item = AgendaItem.create!(meeting: meeting, title: "Parking Enforcement Update", order_index: 2)
    AgendaItemTopic.create!(agenda_item: child, topic: topic)
    AgendaItemTopic.create!(agenda_item: legacy_item, topic: topic)
    AgendaItemTopic.create!(agenda_item: section, topic: topic)

    query = Topics::RetrievalQueryBuilder.new(topic, meeting).build_query

    assert_includes query, "NEW BUSINESS — Parking Ramp Expansion"
    assert_includes query, "Parking Enforcement Update"
    refute_match(/Current Agenda: .*NEW BUSINESS(,|\.|$)/, query)
  end
end
