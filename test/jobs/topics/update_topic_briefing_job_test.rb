require "test_helper"
require "minitest/mock"

class Topics::UpdateTopicBriefingJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking", status: "approved")
    @future_meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 3.days.from_now,
      detail_page_url: "http://example.com/future"
    )
    @item = @future_meeting.agenda_items.create!(
      title: "Downtown Parking Discussion",
      order_index: 1
    )
  end

  test "tier headline_only creates briefing from meeting data without AI" do
    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_includes briefing.headline, "City Council"
    assert_equal "headline_only", briefing.generation_tier
    assert_nil briefing.editorial_content
    assert_nil briefing.record_content
  end

  test "tier headline_only updates existing briefing without overwriting full" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "Existing full headline",
      editorial_content: "Full editorial",
      record_content: "Full record",
      generation_tier: "full",
      last_full_generation_at: 1.day.ago
    )

    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    briefing = @topic.reload.topic_briefing
    assert_equal "full", briefing.generation_tier
    assert_equal "Full editorial", briefing.editorial_content
  end

  test "tier interim calls lightweight AI and updates headline and editorial" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :generate_briefing_interim, {
      "headline" => "Council to vote on parking plan, #{@future_meeting.starts_at.strftime('%b %-d')}",
      "upcoming_note" => "The revised proposal reduces conversion from 12 to 8 spots."
    } do |arg|
      arg.is_a?(Hash)
    end

    Ai::OpenAiService.stub :new, mock_ai do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @future_meeting.id,
        tier: "interim"
      )
    end

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_includes briefing.headline, "parking plan"
    assert_includes briefing.editorial_content, "revised proposal"
    assert_equal "interim", briefing.generation_tier

    mock_ai.verify
  end

  test "skips non-approved topics" do
    @topic.update!(status: "proposed")

    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    assert_nil @topic.reload.topic_briefing
  end

  test "is idempotent for headline_only" do
    2.times do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @future_meeting.id,
        tier: "headline_only"
      )
    end

    assert_equal 1, TopicBriefing.where(topic: @topic).count
  end
end
