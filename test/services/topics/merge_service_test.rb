require "test_helper"

module Topics
  class MergeServiceTest < ActiveSupport::TestCase
    include ActiveJob::TestHelper

    setup do
      clear_enqueued_jobs
    end

    test "rejects self merge" do
      topic = Topic.create!(name: "property tax")

      assert_raises(ArgumentError) do
        MergeService.new(source_topic: topic, target_topic: topic).call
      end

      assert Topic.exists?(topic.id)
    end

    test "moves knowledge links and dedupes colliding summaries" do
      source_topic = Topic.create!(name: "property tax levy")
      target_topic = Topic.create!(name: "property tax")
      meeting = Meeting.create!(
        body_name: "City Council",
        meeting_type: "Regular",
        starts_at: Time.current,
        status: "minutes_posted",
        detail_page_url: "http://example.com/meeting/merge-service"
      )
      knowledge_source = KnowledgeSource.create!(
        title: "Budget note",
        source_type: "note",
        origin: "manual",
        status: "approved"
      )

      KnowledgeSourceTopic.create!(knowledge_source: knowledge_source, topic: source_topic)
      TopicSummary.create!(topic: source_topic, meeting: meeting, summary_type: "topic_digest", content: "source", generation_data: { source: "test" })
      TopicSummary.create!(topic: target_topic, meeting: meeting, summary_type: "topic_digest", content: "target", generation_data: { source: "test" })
      TopicReviewEvent.create!(topic: source_topic, action: "merged", automated: true)

      MergeService.new(source_topic: source_topic, target_topic: target_topic).call

      assert_equal [ target_topic.id ], knowledge_source.reload.topic_ids
      summaries = TopicSummary.where(topic: target_topic, meeting: meeting, summary_type: "topic_digest")
      assert_equal 1, summaries.count
      assert_equal "target", summaries.first.content
      assert_equal 1, target_topic.reload.topic_review_events.count
      assert_not Topic.exists?(source_topic.id)
      assert_enqueued_with(job: Topics::UpdateContinuityJob, args: [ { topic_id: target_topic.id } ])
    end

    test "rejects merge when another topic already owns the source-name alias" do
      source_topic = Topic.create!(name: "property tax levy")
      target_topic = Topic.create!(name: "property tax")
      other_topic = Topic.create!(name: "budget")
      TopicAlias.create!(topic: other_topic, name: "property tax levy")

      assert_raises(ArgumentError) do
        MergeService.new(source_topic: source_topic, target_topic: target_topic).call
      end

      assert Topic.exists?(source_topic.id)
      assert_not TopicAlias.exists?(topic: target_topic, name: "property tax levy")
      assert TopicAlias.exists?(topic: other_topic, name: "property tax levy")
    end

    test "enqueues future briefing updates for migrated future agenda items" do
      source_topic = Topic.create!(name: "harbor project")
      target_topic = Topic.create!(name: "downtown project", status: "approved")
      meeting = Meeting.create!(
        body_name: "City Council",
        meeting_type: "Regular",
        starts_at: 2.days.from_now,
        status: "scheduled",
        detail_page_url: "http://example.com/meeting/future-merge-service"
      )
      agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Future item", order_index: 1)
      AgendaItemTopic.create!(topic: source_topic, agenda_item: agenda_item)
      clear_enqueued_jobs

      MergeService.new(source_topic: source_topic, target_topic: target_topic).call

      assert_enqueued_with(
        job: Topics::UpdateTopicBriefingJob,
        args: [ { topic_id: target_topic.id, meeting_id: meeting.id, tier: "headline_only" } ]
      )
    end
  end
end
