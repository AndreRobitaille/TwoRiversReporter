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
      @section = @meeting.agenda_items.create!(
        title: "PUBLIC WORKS",
        kind: "section",
        order_index: 0
      )
      # Creating the AgendaItemTopic link also creates the TopicAppearance
      # via AgendaItemTopic#create_appearance_and_update_continuity callback.
      @agenda_item.topics << @topic
      AgendaItemTopic.create!(agenda_item: @section, topic: @topic)

      # Prior appearance
      @prior_meeting = Meeting.create!(
        body_name: "City Council",
        starts_at: 1.month.ago,
        detail_page_url: "http://example.com/prior"
      )
      prior_item = @prior_meeting.agenda_items.create!(title: "Prior Street Repair", order_index: 1)
      AgendaItemTopic.create!(agenda_item: prior_item, topic: @topic)

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

    test "excludes structural agenda rows from agenda_items" do
      context = @builder.build_context_json

      refute_includes context[:agenda_items].map { |item| item[:title] }, "PUBLIC WORKS"
      refute_includes context[:citation_ids], "agenda-#{@section.id}"
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

    test "uses parent context in citation label for child agenda items" do
      child = @meeting.agenda_items.create!(
        title: "Repair Main St Bridge",
        summary: "Bridge work.",
        order_index: 2,
        parent: @section
      )
      AgendaItemTopic.create!(agenda_item: child, topic: @topic)

      context = SummaryContextBuilder.new(@topic, @meeting).build_context_json
      child_entry = context[:agenda_items].find { |item| item[:id] == child.id }

      assert_includes child_entry[:citation][:label], "PUBLIC WORKS"
      assert_equal "PUBLIC WORKS — Repair Main St Bridge", child_entry[:title]
    end

    test "does not match ambiguous bare item_details titles across sections" do
      other_section = @meeting.agenda_items.create!(title: "CONSENT AGENDA", kind: "section", order_index: 2)
      child = @meeting.agenda_items.create!(title: "Resolution", kind: "item", parent: @section, order_index: 3)
      other_child = @meeting.agenda_items.create!(title: "Resolution", kind: "item", parent: other_section, order_index: 4)
      AgendaItemTopic.create!(agenda_item: child, topic: @topic)
      AgendaItemTopic.create!(agenda_item: other_child, topic: @topic)

      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: {
          "item_details" => [
            { "agenda_item_title" => "Resolution", "summary" => "Ambiguous summary" }
          ]
        }
      )

      context = @builder.build_context_json
      resolution_entries = context[:agenda_items].select { |item| item[:title].end_with?("Resolution") }

      assert resolution_entries.all? { |item| item[:item_details_summary].nil? }
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

    test "includes item_details_summary when meeting has a MeetingSummary with matching item_details" do
      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: {
          "item_details" => [
            {
              "agenda_item_title" => "Repair Main St",
              "summary" => "Council approved a $240,000 bid for Main St repaving from Smith Paving Co.",
              "activity_level" => "decision",
              "vote" => "5-0",
              "decision" => "approved",
              "public_hearing" => nil
            }
          ]
        }
      )

      context = @builder.build_context_json
      item = context[:agenda_items].first

      assert_equal "Council approved a $240,000 bid for Main St repaving from Smith Paving Co.",
        item[:item_details_summary]
      assert_equal "decision", item[:item_details_activity_level]
      assert_equal "5-0", item[:item_details_vote]
      assert_equal "approved", item[:item_details_decision]
      assert_nil item[:item_details_public_hearing]
    end

    test "leaves item_details_* fields nil when meeting has no MeetingSummary" do
      # @meeting is set up without a MeetingSummary in the default setup
      context = @builder.build_context_json
      item = context[:agenda_items].first

      assert_nil item[:item_details_summary]
      assert_nil item[:item_details_activity_level]
      assert_nil item[:item_details_vote]
      assert_nil item[:item_details_decision]
      assert_nil item[:item_details_public_hearing]
    end

    test "matches item_details entries by normalized agenda title (numbering + 'as needed')" do
      # Agenda item has no leading number and no suffix; item_details entry has both.
      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: {
          "item_details" => [
            {
              "agenda_item_title" => "7. REPAIR MAIN ST, AS NEEDED",
              "summary" => "Committee discussed Main St potholes; no action.",
              "activity_level" => "discussion",
              "vote" => nil,
              "decision" => nil,
              "public_hearing" => nil
            }
          ]
        }
      )

      context = @builder.build_context_json
      item = context[:agenda_items].first

      assert_equal "Committee discussed Main St potholes; no action.",
        item[:item_details_summary],
        "TitleNormalizer should strip leading '7.' and trailing ', AS NEEDED' to match"
      assert_equal "discussion", item[:item_details_activity_level]
    end

    test "ignores item_details entries whose title does not match any linked agenda item" do
      # Two item_details entries: one matches the linked agenda item ("Repair Main St"),
      # one is for an unrelated item that is not in agenda_items for this topic.
      # The unrelated entry should be silently ignored — not cause an error, not
      # appear in the returned agenda_items output.
      @meeting.meeting_summaries.create!(
        summary_type: "minutes_recap",
        generation_data: {
          "item_details" => [
            {
              "agenda_item_title" => "Repair Main St",
              "summary" => "Council approved the paving bid.",
              "activity_level" => "decision",
              "vote" => "5-0",
              "decision" => "approved",
              "public_hearing" => nil
            },
            {
              "agenda_item_title" => "UNRELATED TOPIC NOBODY LINKED",
              "summary" => "Some other content that should not leak.",
              "activity_level" => "discussion",
              "vote" => nil,
              "decision" => nil,
              "public_hearing" => nil
            }
          ]
        }
      )

      context = @builder.build_context_json
      items = context[:agenda_items]

      # Only the linked agenda item ("Repair Main St") appears in the output —
      # the builder filters agenda_items to those with AgendaItemTopic links
      # to the target topic.
      assert_equal 1, items.size
      assert_equal "Council approved the paving bid.", items.first[:item_details_summary]
      assert_equal "decision", items.first[:item_details_activity_level]

      # The unrelated entry's content should not leak into the output at all.
      assert_nil(items.find { |i| i[:item_details_summary].to_s.include?("should not leak") })
    end
  end
end
