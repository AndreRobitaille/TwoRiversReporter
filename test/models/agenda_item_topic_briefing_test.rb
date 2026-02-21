require "test_helper"

class AgendaItemTopicBriefingTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  test "creating agenda_item_topic for future meeting enqueues headline briefing" do
    topic = Topic.create!(name: "Test Topic", status: "approved")
    meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 3.days.from_now,
      detail_page_url: "http://example.com/future"
    )
    item = meeting.agenda_items.create!(title: "Test Item", order_index: 1)

    assert_enqueued_with(job: Topics::UpdateTopicBriefingJob) do
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end
  end

  test "creating agenda_item_topic for past meeting does not enqueue headline briefing" do
    topic = Topic.create!(name: "Test Topic", status: "approved")
    meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/past"
    )
    item = meeting.agenda_items.create!(title: "Test Item", order_index: 1)

    assert_no_enqueued_jobs(only: Topics::UpdateTopicBriefingJob) do
      AgendaItemTopic.create!(agenda_item: item, topic: topic)
    end
  end
end
