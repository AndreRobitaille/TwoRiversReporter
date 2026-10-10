require "test_helper"

class Citations::PipelineTest < ActiveSupport::TestCase
  setup do
    seed_prompt_templates
    prompt = PromptTemplateData::PROMPTS.fetch("analyze_meeting_content")
    PromptTemplate.find_by!(key: "analyze_meeting_content").update!(**prompt)
    @meeting = Meeting.create!(body_name: "City Council Work Session", starts_at: 1.day.ago,
      detail_page_url: "https://city.example.test/meeting")
    @topic = Topic.create!(name: "Synthetic contract", status: "approved")
    @item = @meeting.agenda_items.create!(title: "Synthetic contract", order_index: 1)
    @item.topics << @topic
    @service = Ai::OpenAiService.new
    @retrieval = Object.new
    def @retrieval.retrieve_context(*); []; end
    def @retrieval.format_context(*); ""; end
  end

  test "transcript with a packet keeps recording provenance across every boundary" do
    packet = @meeting.meeting_documents.create!(document_type: "packet_pdf", extracted_text: "Scheduled contract.",
      source_url: "https://city.example.test/packet.pdf")
    transcript = document("transcript", "FIRST_RECORDING_EVIDENCE. MIDDLE_RECORDING_EVIDENCE. FINAL_RECORDING_EVIDENCE.")
    summary = generate_summary(transcript)
    verify_pipeline(summary, transcript, "whole_source")
    assert_equal [ packet.id, transcript.id ], summary.generation_data["source_catalog"].map { |source| source["document_id"] }
    assert_includes PromptRun.where(source: @meeting).recent.first.placeholder_values["doc_text"], packet.extracted_text
  end

  test "uploading a transcript preserves packet page evidence through recap topic and API boundaries" do
    packet = document("packet_pdf", "DISTINCTIVE_OFFICIAL_PROPOSAL. The repair budget is $12,000.", page_count: 2)
    packet.extractions.create!(page_number: 2, cleaned_text: packet.extracted_text)
    document("packet_html", "")
    transcript = document("transcript", "FIRST_RECORDING_EVIDENCE. Discussion continued. FINAL_RECORDING_EVIDENCE.")
    recording_reference = { "source_id" => "doc-#{transcript.id}", "location" => { "kind" => "whole_source" } }
    summary = generate_summary(packet, location: { "kind" => "pdf_page", "page_number" => 2 },
      additional_references: [ recording_reference ])
    assert_equal "transcript_recap", summary.summary_type
    verify_pipeline(summary, packet, "pdf_page")
    run = PromptRun.where(source: @meeting).for_template("analyze_meeting_content").recent.first
    %w[DISTINCTIVE_OFFICIAL_PROPOSAL FIRST_RECORDING_EVIDENCE FINAL_RECORDING_EVIDENCE].each do |marker|
      assert_includes run.messages.last["content"], marker
    end
    assert_equal [ packet.id, transcript.id ], summary.generation_data["source_catalog"].map { |source| source["document_id"] }
    references = summary.generation_data["item_details"].first["citations"]
    assert_equal [ packet.id, transcript.id ], references.map { |reference| reference["document_id"] }
    context = Topics::SummaryContextBuilder.new(@topic, @meeting).build_context_json
    assert_equal references, context[:agenda_items].first[:item_details_citations].map(&:deep_stringify_keys)
    recent_references = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build.first[:citations]
    assert_equal references, recent_references.map { |reference| reference.deep_stringify_keys.slice(*references.first.keys) }
  end

  test "recap retains agenda pages when a packet has no usable text" do
    document("packet_pdf", "")
    agenda = document("agenda_pdf", "DISTINCTIVE_AGENDA_PROPOSAL.", page_count: 1)
    agenda.extractions.create!(page_number: 1, cleaned_text: agenda.extracted_text)
    transcript = document("transcript", "Distinctive recorded discussion.")
    summary = generate_summary(agenda, location: { "kind" => "pdf_page", "page_number" => 1 })
    verify_pipeline(summary, agenda, "pdf_page")
    assert_equal [ agenda.id, transcript.id ], summary.generation_data["source_catalog"].map { |source| source["document_id"] }
  end

  test "earlier votes included in a packet cannot validate a current meeting outcome" do
    packet = document("packet_pdf", "Previous meeting minutes: The motion passed 6-2.")
    document("transcript", "All in favor? Aye. Motion carries.")
    summary = generate_summary(packet, item_attributes: {
      "decision" => "Passed", "vote" => "6-2", "vote_evidence" => "The motion passed 6-2." })
    assert_includes PromptRun.where(source: @meeting).recent.first.placeholder_values["doc_text"], packet.extracted_text
    assert_equal "Passed", summary.generation_data["item_details"].first["decision"]
    assert_nil summary.generation_data["item_details"].first["vote"]
  end

  test "official minutes retain packet pages and supplementary recording without losing source type" do
    minutes = document("minutes_pdf", "Distinctive approved minutes.")
    packet = document("packet_pdf", "Distinctive official proposal.", page_count: 1)
    packet.extractions.create!(page_number: 1, cleaned_text: packet.extracted_text)
    transcript = document("transcript", "Distinctive supplemental discussion.")
    summary = generate_summary(packet, location: { "kind" => "pdf_page", "page_number" => 1 })
    assert_equal "minutes_with_transcript", summary.generation_data["source_type"]
    assert_equal [ minutes.id, packet.id, transcript.id ], summary.generation_data["source_catalog"].map { |source| source["document_id"] }
    verify_pipeline(summary, packet, "pdf_page")

    transcript.destroy!
    @meeting.reload
    summary = generate_summary(packet, location: { "kind" => "pdf_page", "page_number" => 1 })
    assert_equal "minutes", summary.generation_data["source_type"]
    assert_equal [ minutes.id, packet.id ], summary.generation_data["source_catalog"].map { |source| source["document_id"] }
  end

  test "PDF-only recap preserves the actual page identity across every boundary" do
    minutes = document("minutes_pdf", "Approved contract.", page_count: 3)
    minutes.extractions.create!(page_number: 3, cleaned_text: minutes.extracted_text)
    summary = generate_summary(minutes, location: { "kind" => "pdf_page", "page_number" => 3 })
    verify_pipeline(summary, minutes, "pdf_page")
    result = Citations::Resolver.for_summary(summary).resolve_all(summary.generation_data["highlights"].first["citations"]).first
    assert_equal 3, result[:page_number]
    assert_equal "#{minutes.source_url}#page=3", result[:source_url]
  end

  test "combined recap attributes supplemental evidence only to the recording" do
    minutes = document("minutes_pdf", "Minutes record brief business.", page_count: 1)
    minutes.extractions.create!(page_number: 1, cleaned_text: minutes.extracted_text)
    transcript = document("transcript", "Recording supplied the contract discussion.")
    summary = generate_summary(transcript)
    assert_equal "minutes_with_transcript", summary.generation_data["source_type"]
    assert_equal [ minutes.id, transcript.id ], summary.generation_data["source_catalog"].map { |source| source["document_id"] }
    verify_pipeline(summary, transcript, "whole_source")
    context = Topics::SummaryContextBuilder.new(@topic, @meeting).build_context_json
    assert_equal [ transcript.id ], context[:agenda_items].first[:item_details_citations].map { |citation| citation[:document_id] }
  end

  test "an invalid location or a source replaced during the AI call leaves the existing summary intact" do
    transcript = document("transcript", "Original evidence.")
    summary = @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: { "headline" => "Original report." })
    before = summary.attributes
    assert_raises(Citations::SourceCatalog::InvalidSource) do
      generate_summary(transcript, location: { "kind" => "pdf_page", "page_number" => 1 })
    end
    assert_equal before, summary.reload.attributes
    assert_raises(Citations::SourceCatalog::InvalidSource) do
      generate_summary(transcript) { transcript.update!(extracted_text: "Replacement evidence.") }
    end
    assert_equal before, summary.reload.attributes
  end

  test "legacy topic context is unresolved and never selects a newer document by summary type" do
    document("minutes_pdf", "Replacement minutes.")
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      "source_type" => "minutes", "item_details" => [ { "agenda_item_id" => @item.id,
        "summary" => "Legacy reporting.", "citations" => [ "Page 1" ] } ] })
    context = Topics::SummaryContextBuilder.new(@topic, @meeting).build_context_json
    assert_empty context[:agenda_items].first[:item_details_citations]
    assert_equal "unresolved", context[:agenda_items].first[:item_details_unresolved_citations].first[:status]
    assert_empty context[:source_catalog]
  end

  test "rolling briefing stores the same validated reference and source catalog" do
    transcript = document("transcript", "Recording contract evidence.")
    summary = generate_summary(transcript)
    verify_pipeline(summary, transcript, "whole_source")
    reference = summary.generation_data["item_details"].first["citations"].first
    captured_context = nil
    fake_ai = Object.new
    fake_ai.define_singleton_method(:analyze_topic_briefing) do |context, **|
      captured_context = context
      { "headline" => "Synthetic reporting", "factual_record" => [ { "event" => "Distinctive recorded detail.",
        "date" => "2026-10-01", "meeting" => "City Council Work Session",
        "citations" => [ { "citation_id" => reference["citation_id"], "label" => "Invented page" } ] } ] }.to_json
    end
    fake_ai.define_singleton_method(:render_topic_briefing) do |*, **|
      { "editorial_content" => "Synthetic story.", "record_content" => "Synthetic dated record." }
    end
    def @retrieval.retrieve_topic_context(*, **); []; end
    def @retrieval.format_topic_context(*); []; end
    RetrievalService.stub(:new, @retrieval) do
      Ai::OpenAiService.stub(:new, fake_ai) do
        Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      end
    end
    assert_equal reference, captured_context[:citation_references][reference["citation_id"]].deep_stringify_keys
    briefing = @topic.reload.topic_briefing
    assert_equal [ reference ], briefing.generation_data["factual_record"].first["citations"]
    assert_equal summary.generation_data["source_catalog"], briefing.generation_data["source_catalog"]
  end

  private

  def document(type, text, **attributes)
    @meeting.meeting_documents.create!(document_type: type, extracted_text: text,
      source_url: "https://sources.example.test/#{type}", **attributes)
  end

  def generate_summary(cited_document, location: { "kind" => "whole_source" }, additional_references: [], item_attributes: {})
    reference = { "source_id" => "doc-#{cited_document.id}", "location" => location }
    references = [ reference, *additional_references ]
    data = { "headline" => "Synthetic work-session reporting.", "highlights" => [ {
      "text" => "Distinctive reported highlight.", "citations" => references } ], "public_input" => [],
      "item_details" => [ { "agenda_item_id" => @item.id, "agenda_item_title" => @item.title,
        "summary" => "Distinctive reported detail.", "citations" => references } ] }
    data["item_details"].first.merge!(item_attributes)
    response = lambda do |parameters:|
      yield if block_given?
      { "choices" => [ { "message" => { "content" => data.to_json } } ] }
    end
    @service.instance_variable_get(:@client).stub(:chat, response) do
      SummarizeMeetingJob.new.send(:generate_meeting_summary, @meeting, @service, @retrieval)
    end
    @meeting.meeting_summaries.first
  end

  def verify_pipeline(summary, document, kind)
    run = PromptRun.where(source: @meeting).for_template("analyze_meeting_content").recent.first
    input_catalog = JSON.parse(run.placeholder_values["source_catalog"])
    assert_equal input_catalog, summary.generation_data["source_catalog"]
    assert_includes run.placeholder_values["doc_text"], document.extracted_text
    assert_includes run.messages.last["content"], document.source_url
    reference = summary.generation_data["item_details"].first["citations"].first
    assert_equal document.id, reference["document_id"]
    assert_equal kind, reference.dig("location", "kind")
    context = Topics::SummaryContextBuilder.new(@topic, @meeting).build_context_json
    assert_equal reference, context[:agenda_items].first[:item_details_citations].first.deep_stringify_keys
    recent = Topics::RecentItemDetailsBuilder.new(@topic, [ @meeting ]).build
    assert_equal reference["source_version"], recent.first[:citations].first[:source_version]
    assert_equal document.id, recent.first[:citations].first[:document_id]
    assert_equal "Distinctive reported detail.", recent.first[:summary]
    fake = { "citation_id" => reference["citation_id"], "label" => "Incorrect minutes", "private" => "PRIVATE_CITATION_CANARY" }
    analysis = SummarizeMeetingJob.new.send(:validate_analysis_json,
      { "factual_record" => [ { "statement" => "Distinctive reported detail.", "citations" => [ fake, { "citation_id" => "doc-unknown" } ] } ] },
      context[:citation_ids], context[:citation_references])
    assert_equal [ reference ], analysis["factual_record"].first["citations"]
    refute_includes analysis.to_json, "PRIVATE_CITATION_CANARY"
    SummarizeMeetingJob.new.send(:save_topic_summary, @meeting, @topic, "Synthetic prose.", analysis.merge("source_catalog" => context[:source_catalog]))
    stored_topic = @meeting.topic_summaries.first
    assert_equal reference, stored_topic.generation_data["factual_record"].first["citations"].first
    assert_equal input_catalog, stored_topic.generation_data["source_catalog"]
    serializer = Api::V1::Serializer.new(base_url: "https://example.test")
    api_reference = serializer.summary(@meeting)[:highlights].first[:citations].first
    assert_equal document.id, api_reference[:document_id]
    assert_equal reference["source_version"], api_reference[:source_version]
    assert_equal kind, api_reference.dig(:location, "kind")
    api_item = serializer.agenda_items(@meeting).first[:analysis][:citations].first
    assert_equal api_reference, api_item
  end
end
