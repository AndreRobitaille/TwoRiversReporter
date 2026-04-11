require "test_helper"

class Topics::RecentItemDetailsBuilderTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "garbage and recycling service changes", status: "approved")
    @meeting = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 1.week.ago,
      detail_page_url: "http://example.com/puc-aug"
    )
    @linked_item = @meeting.agenda_items.create!(
      title: "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
      order_index: 1
    )
    AgendaItemTopic.create!(agenda_item: @linked_item, topic: @topic)
  end

  test "returns item_details entries for agenda items linked to the topic" do
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "Staff reported fake stickers showing up on refuse; committee declined to revisit the method.",
            "activity_level" => "discussion",
            "vote" => nil, "decision" => nil, "public_hearing" => nil,
            "citations" => [ "Page 4" ]
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build

    assert_equal 1, result.length
    entry = result.first
    assert_equal @meeting.starts_at.to_date.to_s, entry[:meeting_date]
    assert_equal "Public Utilities Committee", entry[:meeting_body]
    assert_equal "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED", entry[:agenda_item_title]
    assert_includes entry[:summary], "fake stickers"
    assert_equal "discussion", entry[:activity_level]
  end

  test "filters out item_details entries whose agenda_item is not linked to the topic" do
    unlinked_item = @meeting.agenda_items.create!(title: "5. WATER UTILITY UPDATE", order_index: 2)
    # unlinked_item has no AgendaItemTopic pointing at @topic

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "Fake stickers.",
            "activity_level" => "discussion"
          },
          {
            "agenda_item_title" => "5. WATER UTILITY UPDATE",
            "summary" => "Pump replacement underway.",
            "activity_level" => "status_update"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build

    assert_equal 1, result.length
    assert_includes result.first[:summary], "Fake stickers"
    refute(result.any? { |r| r[:summary].to_s.include?("Pump replacement") },
      "water update should not leak into garbage topic context")
  end

  test "returns empty array when meeting has no summary" do
    assert_equal [], Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
  end

  test "returns empty array when summary generation_data has no item_details" do
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => "no item details key" }
    )
    assert_equal [], Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
  end

  test "uses the most recent summary when multiple exist for the same meeting" do
    older = @meeting.meeting_summaries.create!(
      summary_type: "packet_analysis",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "preview guess",
            "activity_level" => "status_update"
          }
        ]
      }
    )
    older.update_columns(created_at: 2.days.ago)

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "real minutes content",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build

    assert_equal 1, result.length
    assert_equal "real minutes content", result.first[:summary]
  end

  test "normalizes item titles before matching (handles numbering variance)" do
    # Agenda item title has no leading number; item_details has a prefix.
    @linked_item.update!(title: "Solid Waste Utility: Updates and Action")

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "real content",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
    assert_equal 1, result.length, "TitleNormalizer should strip numbering and 'as needed' to match"
  end

  test "handles multiple meetings and preserves chronological order" do
    earlier = Meeting.create!(
      body_name: "Public Utilities Committee",
      starts_at: 30.days.ago,
      detail_page_url: "http://example.com/puc-older"
    )
    earlier_item = earlier.agenda_items.create!(title: "SOLID WASTE UTILITY", order_index: 1)
    AgendaItemTopic.create!(agenda_item: earlier_item, topic: @topic)
    earlier.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "SOLID WASTE UTILITY",
            "summary" => "Older meeting content.",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED",
            "summary" => "Newer meeting content.",
            "activity_level" => "discussion"
          }
        ]
      }
    )

    result = Topics::RecentItemDetailsBuilder.new(@topic, [ earlier, @meeting ]).build

    assert_equal 2, result.length
    # Order mirrors the input meetings array so the caller controls
    # chronology. See the fixture setup — earlier is passed first.
    assert_equal "Older meeting content.", result[0][:summary]
    assert_equal "Newer meeting content.", result[1][:summary]
  end
end
