require "test_helper"

module Admin
  module Topics
    class ImpactPreviewQueryTest < ActiveSupport::TestCase
      test "calculates downstream counts for merge preview" do
        target = Topic.create!(name: "harbor dredging")
        source = Topic.create!(name: "harbor project")
        TopicAlias.create!(topic: source, name: "dredging project")
        TopicAlias.create!(topic: source, name: "harbor project")
        meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 1.day.from_now, status: "scheduled", detail_page_url: "http://example.com/meeting/impact")
        agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Dredging contract", order_index: 1)
        AgendaItemTopic.create!(topic: source, agenda_item: agenda_item)
        motion = Motion.create!(meeting: meeting, agenda_item: agenda_item)
        Motion.create!(meeting: meeting, agenda_item: agenda_item)
        Vote.create!(motion: motion, member: Member.create!(name: "Council Member"), value: "yes")
        TopicSummary.create!(topic: source, meeting: meeting, content: "summary", summary_type: "topic_digest", generation_data: { "seed" => true })
        knowledge_source = KnowledgeSource.create!(title: "report", source_type: "note", origin: "manual", status: "approved")
        KnowledgeSourceTopic.create!(knowledge_source: knowledge_source, topic: source)

        preview = ImpactPreviewQuery.new(action: :merge, topic: target, source_topic: source).call

        assert_equal 3, preview.alias_count
        assert_equal 1, preview.appearance_count
        assert_equal 1, preview.future_appearance_count
        assert_equal 2, preview.decision_count
        assert_equal 1, preview.summary_count
        assert_equal 1, preview.knowledge_link_count
        assert_match "harbor project", preview.language
        assert_match "pages/mentions", preview.language
        assert_match "summaries", preview.language
        assert_match "knowledge links", preview.language
        assert_match "Search, detail pages", preview.language
        assert_match "Choose a topic to preview combining it into the current topic.", Admin::Topics::ImpactPreviewQuery.new(action: :merge, topic: target).call.language
      end

      test "counts the source topic name as an alias for merge away previews" do
        source = Topic.create!(name: "harbor project")
        destination = Topic.create!(name: "harbor district")
        TopicAlias.create!(topic: source, name: "dredging project")
        TopicAlias.create!(topic: source, name: "harbor project alternate")

        preview = ImpactPreviewQuery.new(action: :merge_away, topic: source, source_topic: destination).call

        assert_equal 3, preview.alias_count
        assert_match "will update 0 pages/mentions, 3 aliases", preview.language
      end

      test "uses current topic footprint for alias remove and promote previews" do
        topic = Topic.create!(name: "harbor dredging")
        meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 1.day.ago, status: "minutes_posted", detail_page_url: "http://example.com/meeting/impact")
        agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Dredging contract", order_index: 1)
        AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)
        TopicSummary.create!(topic: topic, meeting: meeting, content: "summary", summary_type: "topic_digest", generation_data: { "seed" => true })
        KnowledgeSourceTopic.create!(knowledge_source: KnowledgeSource.create!(title: "report", source_type: "note", origin: "manual", status: "approved"), topic: topic)

        remove_preview = ImpactPreviewQuery.new(action: :remove_alias, topic: topic, alias_name: "harbor project").call
        promote_preview = ImpactPreviewQuery.new(action: :promote_alias, topic: topic, alias_name: "harbor project").call

        assert_equal 1, remove_preview.appearance_count
        assert_equal 1, remove_preview.summary_count
        assert_equal 1, remove_preview.knowledge_link_count
        assert_equal 1, promote_preview.appearance_count
        assert_equal 1, promote_preview.summary_count
        assert_equal 1, promote_preview.knowledge_link_count
      end
    end
  end
end
