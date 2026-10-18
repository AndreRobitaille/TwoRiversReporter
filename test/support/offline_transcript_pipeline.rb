require "digest"

module OfflineTranscriptPipeline
  TAIL = "Closing evidence Ω: the meter review remains a separate discussion."

  private

    def build_pipeline_fixture
      @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago,
        status: "held", detail_page_url: "https://example.test/offline-pipeline")
      @section = @meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
      @items = [ "Harbor walkway review", "Water meter policy review" ].each_with_index.map do |title, index|
        @meeting.agenda_items.create!(title: title, number: index + 1, kind: "item", parent: @section, order_index: index + 1)
      end
      @facts = [ "The harbor walkway proposal was deferred.", "The water meter policy was discussed. #{TAIL}" ]
      @topics = [ "harbor walkway", "water meter policy" ].map do |name|
        Topic.create!(name: name, status: "approved", review_status: "approved", resident_impact_score: 4)
      end
      @items.zip(@topics).each { |item, topic| AgendaItemTopic.create!(agenda_item: item, topic: topic) }
      @minutes = @meeting.meeting_documents.create!(document_type: "minutes_pdf",
        source_url: "https://example.test/offline-minutes.pdf", extracted_text: @facts.first + " The meter policy was discussed.")
      @motion = @meeting.motions.create!(agenda_item: @items.first, description: "Defer the walkway proposal", outcome: "tabled")
      @official_state = [ @minutes.reload.attributes, @motion.reload.attributes ]
      @text = "#{@facts.first}\n#{@facts.last}\n" + ("Supplementary discussion.\n" * 2000) + TAIL
      @srt = "1\n00:00:01,000 --> 00:45:00,000\n#{@text}"
      @boundaries = []
      clear_enqueued_jobs
    end

    def run_pipeline
      with_pipeline_provider { Admin::TranscriptImportWorkflowJob.perform_now(@import.id) }
    end

    def with_pipeline_provider
      test = self
      provider = Object.new
      provider.define_singleton_method(:prepare_kb_context) { |_| "Offline background fixture" }
      provider.define_singleton_method(:analyze_meeting_content) { |text, _kb, type, **options| test.send(:meeting_response, text, type, options) }
      provider.define_singleton_method(:extract_topics) { |text, **options| test.send(:extraction_response, text, options) }
      provider.define_singleton_method(:analyze_topic_summary) { |context, **| test.send(:topic_response, context) }
      provider.define_singleton_method(:render_topic_summary) { |json, **| JSON.parse(json).fetch("factual_record").map { |entry| entry.fetch("text") }.join("\n") }
      provider.define_singleton_method(:analyze_topic_briefing) { |context, **| test.send(:briefing_response, context) }
      provider.define_singleton_method(:render_topic_briefing) { |json, **| { "editorial_content" => JSON.parse(json).fetch("headline"), "record_content" => JSON.parse(json).fetch("factual_record").map { |entry| entry.fetch("text") }.join("\n") } }
      embedding = Object.new
      embedding.define_singleton_method(:embed) { |_| [ 1.0, 0.0 ] }
      Ai::EmbeddingService.stub :new, embedding do
        Ai::OpenAiService.stub :new, provider do
          yield
        end
      end
    end

    def meeting_response(text, type, options)
      document = @meeting.latest_document("transcript")
      assert_uploaded_source(document)
      assert_equal "minutes", type
      assert_includes text, @minutes.extracted_text
      assert_includes options.fetch(:motion_context), @motion.description
      assert text.end_with?(@text), "complete supplementary transcript must reach meeting analysis"
      assert options.fetch(:meeting_record_text).end_with?(@text)
      assert_catalog(options.fetch(:source_catalog), document)
      assert_equal expected_pairs, link_pairs, "both distinct item/topic links must survive"
      @boundaries << :meeting
      details = @items.each_with_index.map do |item, index|
        source = index.zero? ? @minutes : document
        { "agenda_item_id" => item.id, "title" => item.title, "summary" => @facts[index],
          "activity_level" => "discussion", "vote" => nil, "decision" => nil,
          "citations" => [ { "source_id" => "doc-#{source.id}", "location" => { "kind" => "whole_source" } } ] }
      end
      { "headline" => "Two separate civic discussions", "highlights" => details.map(&:dup),
        "public_input" => [], "item_details" => details }.to_json
    end

    def extraction_response(text, options)
      @items.each { |item| assert_includes text, "ID: #{item.id}" }
      assert_not_includes text, "ID: #{@section.id}\n"
      assert_equal "minutes_pdf: #{@minutes.extracted_text}", options.fetch(:meeting_documents_context)
      assert_equal expected_pairs, TopicAppearance.where(meeting: @meeting).pluck(:agenda_item_id, :topic_id).sort, "pruning must retain both substantive identities"
      assert_empty link_pairs, "reanalysis clears old links before real extraction"
      assert_meeting_details
      @boundaries << :extraction
      classifications = @items.zip(@topics).map do |item, topic|
        { "id" => item.id, "category" => "Infrastructure", "tags" => [ topic.name ], "confidence" => 0.9, "topic_worthy" => true }
      end
      if @broken_replacement
        classifications.first["tags"] = [ @broken_replacement.name ]
        classifications.last["confidence"] = { "malformed_provider_value" => true }
      end
      { "items" => classifications }.to_json
    end

    def topic_response(context)
      index = @topics.index { |topic| topic.id == context.fetch(:topic_metadata).fetch(:id) }
      assert_not_nil index
      assert_equal [ @items[index].id ], context.fetch(:agenda_items).map { |item| item.fetch(:id) }
      item = context.fetch(:agenda_items).sole
      assert_equal @facts[index], item.fetch(:item_details_summary)
      assert_equal "minutes_with_transcript", context.fetch(:meeting_metadata).fetch(:source_type)
      assert_catalog(context.fetch(:source_catalog), @meeting.latest_document("transcript"))
      @boundaries << [ :topic, @topics[index].id ]
      topic_analysis(index, item.fetch(:item_details_citations).sole.fetch(:citation_id))
    end

    def briefing_response(context)
      index = @topics.index { |topic| topic.id == context.fetch(:topic_metadata).fetch(:id) }
      assert_not_nil index
      assert_equal [ @items[index].id ], context.fetch(:recent_raw_context).map { |item| item.fetch(:id) }
      details = context.fetch(:recent_item_details)
      assert_equal [ @items[index].id ], details.map { |item| item.fetch(:agenda_item_id) }
      assert_equal @facts[index], details.sole.fetch(:summary)
      assert_equal @facts[index], context.fetch(:prior_meeting_analyses).sole.fetch("factual_record").sole.fetch("text")
      assert_catalog(context.fetch(:source_catalog), @meeting.latest_document("transcript"))
      @boundaries << [ :briefing, @topics[index].id ]
      topic_analysis(index, context.fetch(:recent_raw_context).sole.fetch(:item_details_citations).sole.fetch(:citation_id))
    end

    def topic_analysis(index, citation_id)
      { "headline" => @topics[index].name, "resident_impact" => { "score" => 4 },
        "factual_record" => [ { "text" => @facts[index], "event" => @facts[index], "date" => @meeting.starts_at.to_date.iso8601, "meeting" => @meeting.body_name, "citations" => [ { "citation_id" => citation_id, "source_url" => "https://example.test/model-invented-source" } ] } ] }.to_json
    end

    def assert_complete_state
      assert_equal "completed", @import.reload.status, @import.error_message
      assert_equal @topics.map(&:id).sort, @import.affected_topic_ids
      assert_uploaded_source(@import.meeting_document)
      assert_meeting_details
      assert_equal expected_pairs, link_pairs, "both distinct item/topic links must survive"
      assert_equal expected_pairs, TopicAppearance.where(meeting: @meeting).pluck(:agenda_item_id, :topic_id).sort
      assert_equal @topics.map(&:id).sort, @meeting.topic_summaries.pluck(:topic_id).sort
      @topics.each_with_index do |topic, index|
        summary = @meeting.topic_summaries.find_by!(topic: topic)
        briefing = topic.reload.topic_briefing
        assert_not_nil briefing
        [ summary, briefing ].each do |record|
          assert_catalog(record.generation_data.fetch("source_catalog", []), @import.meeting_document)
          assert_equal @facts[index], record.generation_data.fetch("factual_record").sole.fetch("text")
          assert_includes record.respond_to?(:record_content) ? record.record_content : record.content, @facts[index]
          reference = record.generation_data.fetch("factual_record").sole.fetch("citations").sole
          assert_equal "whole_source", reference.dig("location", "kind"), "reanalysis must retain a canonical source location"
          expected_document = index.zero? ? @minutes : @import.meeting_document
          assert_equal expected_document.id, reference.fetch("document_id")
          resolver = Citations::Resolver.new(meeting: @meeting, catalog: record.generation_data.fetch("source_catalog"))
          resolved = resolver.resolve(reference)
          assert_equal "resolved", resolved.fetch(:status)
          assert_equal expected_document.source_url, resolved.fetch(:source_url)
          assert_not reference.key?("source_url"), "model-supplied URLs are not retained"
        end
        assert_equal @meeting.starts_at, topic.last_seen_at
        assert_equal @meeting.id, briefing.triggering_meeting_id
        assert_equal "full", briefing.generation_tier
      end
      finish = @import.step_logs.reverse.find { |entry| entry["message"] == "Meeting reanalysis finished" }
      %w[before_topic_ids after_topic_ids affected_topic_ids].each do |key|
        assert_equal @topics.map(&:id).sort, finish.fetch("metadata").fetch(key).sort
      end
      assert_equal 1, @boundaries.count(:meeting)
      assert_equal 1, @boundaries.count(:extraction)
      @topics.each do |topic|
        assert_equal 2, @boundaries.count([ :topic, topic.id ])
        assert_equal 1, @boundaries.count([ :briefing, topic.id ])
      end
      assert_official_state
    end

    def assert_meeting_details
      summary = @meeting.meeting_summaries.sole
      assert_equal "minutes_recap", summary.summary_type
      assert_equal "minutes_with_transcript", summary.generation_data.fetch("source_type")
      assert_equal @items.map(&:id), summary.generation_data.fetch("item_details").map { |entry| entry.fetch("agenda_item_id") }
      assert_equal @facts, summary.generation_data.fetch("item_details").map { |entry| entry.fetch("summary") }
      assert_equal [ nil, nil ], summary.generation_data.fetch("item_details").map { |entry| entry.fetch("vote") }
      assert_catalog(summary.generation_data.fetch("source_catalog"), @meeting.latest_document("transcript"))
    end

    def assert_uploaded_source(document)
      assert_not_nil document
      assert_equal @text, document.extracted_text
      assert_equal @text.length, document.text_chars, "uploaded text_chars must count Unicode characters"
      assert_equal @srt.b, document.file.download.b
      assert_equal Digest::MD5.base64digest(@srt), document.file.blob.checksum
    end

    def assert_catalog(sources, document)
      assert_equal [ @minutes.id, document.id ].sort, sources.map { |source| source.fetch("document_id") }.uniq.sort, "retained catalog must include official minutes and supplementary transcript"
      transcript = sources.find { |source| source["document_id"] == document.id }
      assert_equal Digest::SHA256.hexdigest(@text), transcript.fetch("text_sha256")
      assert_equal document.file.blob.checksum, transcript.fetch("attachment_checksum")
      assert_equal [], transcript.fetch("pages"), "transcript remains unpaginated supplementary evidence"
    end

    def assert_official_state
      assert_equal @official_state, [ @minutes.reload.attributes, @motion.reload.attributes ]
      assert_empty @motion.votes
    end

    def expected_pairs
      @items.zip(@topics).map { |item, topic| [ item.id, topic.id ] }.sort
    end

    def link_pairs
      AgendaItemTopic.where(agenda_item: @items).pluck(:agenda_item_id, :topic_id).sort
    end

    def persistent_ids
      [ @items.map(&:id), @topics.map(&:id), TopicAppearance.where(meeting: @meeting).order(:id).pluck(:id),
        @meeting.topic_summaries.order(:id).pluck(:id), @topics.map { |topic| topic.reload.topic_briefing.id } ]
    end
end
