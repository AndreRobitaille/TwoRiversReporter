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
    AgendaItemTopic.create!(agenda_item: @item, topic: @topic)
  end

  test "tier headline_only creates briefing with upcoming_headline" do
    Topics::UpdateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @future_meeting.id,
      tier: "headline_only"
    )

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_includes briefing.upcoming_headline, "City Council"
    assert_equal "Topic update", briefing.headline
    assert_equal "headline_only", briefing.generation_tier
  end

  test "tier headline_only updates upcoming_headline without overwriting full briefing" do
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
    assert_equal "Existing full headline", briefing.headline
    assert_equal "Full editorial", briefing.editorial_content
    assert_includes briefing.upcoming_headline, "City Council"
  end

  test "tier interim saves forward-looking headline to upcoming_headline" do
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
    assert_includes briefing.upcoming_headline, "parking plan"
    assert_equal "Topic update", briefing.headline
    assert_includes briefing.editorial_content, "revised proposal"
    assert_equal "interim", briefing.generation_tier

    mock_ai.verify
  end

  test "tier interim excludes structural agenda rows and keeps parent context" do
    section = @future_meeting.agenda_items.create!(
      title: "NEW BUSINESS",
      kind: "section",
      order_index: 0
    )
    child = @future_meeting.agenda_items.create!(
      title: "Parking Ramp Expansion",
      kind: "item",
      parent: section,
      order_index: 2
    )
    AgendaItemTopic.create!(agenda_item: child, topic: @topic)
    AgendaItemTopic.create!(agenda_item: section, topic: @topic)

    captured_context = nil
    mock_ai = Minitest::Mock.new
    mock_ai.expect :generate_briefing_interim, {
      "headline" => "Council to review parking agenda",
      "upcoming_note" => "Note"
    } do |arg|
      captured_context = arg
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @future_meeting.id,
        tier: "interim"
      )
    end

    titles = captured_context[:agenda_items].map { |item| item[:title] }
    assert_includes titles, "NEW BUSINESS — Parking Ramp Expansion"
    refute_includes titles, "NEW BUSINESS"
    mock_ai.verify
  end

  test "tier interim does not downgrade full briefing tier" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "Full briefing headline",
      editorial_content: "Full editorial",
      generation_tier: "full",
      last_full_generation_at: 1.day.ago
    )

    mock_ai = Minitest::Mock.new
    mock_ai.expect :generate_briefing_interim, {
      "headline" => "Council votes on parking soon",
      "upcoming_note" => "New proposal coming."
    } do |_| true end

    Ai::OpenAiService.stub :new, mock_ai do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: @topic.id,
        meeting_id: @future_meeting.id,
        tier: "interim"
      )
    end

    briefing = @topic.reload.topic_briefing
    assert_equal "full", briefing.generation_tier
    assert_equal "Full briefing headline", briefing.headline
    assert_equal "Council votes on parking soon", briefing.upcoming_headline
    assert_includes briefing.editorial_content, "New proposal coming"
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

  test "skips when topic has only structural agenda items for the meeting" do
    section_only_topic = Topic.create!(name: "Section Only Topic", status: "approved")
    section = @future_meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
    AgendaItemTopic.create!(topic: section_only_topic, agenda_item: section)

    assert_nothing_raised do
      Topics::UpdateTopicBriefingJob.perform_now(
        topic_id: section_only_topic.id,
        meeting_id: @future_meeting.id,
        tier: "interim"
      )
    end

    assert_nil section_only_topic.reload.topic_briefing
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
