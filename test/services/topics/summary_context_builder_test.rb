require "test_helper"

module Topics
  class SummaryContextBuilderTest < ActiveSupport::TestCase
    setup do
      @meeting = Meeting.create!(
        body_name: "City Council",
        starts_at: 1.day.ago,
        detail_page_url: "http://example.com/meeting"
      )
      @topic = Topic.create!(name: "Street Repair", status: "approved")

      # Agenda item link
      @agenda_item = @meeting.agenda_items.create!(
        title: "Repair Main St",
        summary: "Proposal to repair.",
        recommended_action: "Approve.",
        order_index: 1
      )
      @agenda_item.topics << @topic

      # Continuity link
      @topic.topic_appearances.create!(
        meeting: @meeting,
        agenda_item: @agenda_item,
        appeared_at: @meeting.starts_at,
        evidence_type: "agenda_item",
        body_name: "City Council"
      )

      # Prior appearance
      @prior_meeting = Meeting.create!(
        body_name: "City Council",
        starts_at: 1.month.ago,
        detail_page_url: "http://example.com/prior"
      )
      @topic.topic_appearances.create!(
        meeting: @prior_meeting,
        appeared_at: @prior_meeting.starts_at,
        evidence_type: "agenda_item",
        body_name: "City Council"
      )

      @builder = SummaryContextBuilder.new(@topic, @meeting)
    end

    test "builds topic metadata correctly" do
      context = @builder.build_context_json
      meta = context[:topic_metadata]

      assert_equal @topic.canonical_name, meta[:canonical_name]
      assert_equal @topic.id, meta[:id]
    end

    test "includes linked agenda items" do
      context = @builder.build_context_json
      items = context[:agenda_items]

      assert_equal 1, items.size
      assert_equal "Repair Main St", items.first[:title]
      assert_equal "Proposal to repair.", items.first[:summary]
    end

    test "includes continuity context" do
      context = @builder.build_context_json
      continuity = context[:continuity_context]

      assert_not_nil continuity[:recent_status_events]

      # Check prior appearances (should include the one from 1 month ago)
      priors = continuity[:prior_appearances]
      assert_equal 1, priors.size
      assert_equal @prior_meeting.starts_at.to_date, priors.first[:date]
    end

    test "handles document attachments if present" do
      doc = @meeting.meeting_documents.create!(
        document_type: "attachment_pdf",
        source_url: "http://example.com/doc.pdf",
        extracted_text: "Preview text"
      )

      AgendaItemDocument.create!(agenda_item: @agenda_item, meeting_document: doc)

      context = @builder.build_context_json
      attachments = context[:agenda_items].first[:attachments]

      assert_equal 1, attachments.size
      assert_equal "Preview text", attachments.first[:text_preview]
      assert_includes context[:citation_ids], "agenda-#{@agenda_item.id}"
    end

    test "includes resident reported context when present" do
      @topic.update!(source_notes: "Residents raised concerns about data centers", source_type: "social_media")
      builder = SummaryContextBuilder.new(@topic, @meeting)

      context = builder.build_context_json
      resident_context = context[:resident_reported_context]

      assert_equal "Resident-reported (no official record)", resident_context[:label]
      assert_equal "social_media", resident_context[:source_type]
      assert_equal "Residents raised concerns about data centers", resident_context[:notes]
    end
  end
end
