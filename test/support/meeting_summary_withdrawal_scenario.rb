require "minitest/mock"
require "open-uri"

module MeetingSummaryWithdrawalScenario
  CLAIM = "Summarysourcewithdrawalprobe".freeze
  SECOND_CLAIM = "Secondsummarysourceprobe".freeze

  def build_summary_withdrawal_scenario
    @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/summary-withdrawal")
    @items = [ "Synthetic library renovation", "Synthetic harbor maintenance" ].each_with_index.map do |title, index|
      @meeting.agenda_items.create!(title: title, number: (index + 1).to_s, order_index: index + 1)
    end
    @document = @meeting.meeting_documents.create!(document_type: "agenda_pdf", source_url: "https://example.test/summary-agenda.pdf")
    @source_text = @items.map(&:title).join(". ")
    download_summary_source(@source_text)
    Documents::PublishText.new(@document.reload).call(raw_pages: [ @source_text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    @response_data = { headline: CLAIM, highlights: [], public_input: [], item_details: @items.each_with_index.map do |item, index|
      { agenda_item_title: item.title, summary: index.zero? ? CLAIM : SECOND_CLAIM, activity_level: "status_update",
        citations: [ { source_id: "doc-#{@document.id}", location: { kind: "whole_source" } } ] }
    end }
    @provider = Object.new
    response_data = @response_data
    @provider.define_singleton_method(:prepare_kb_context) { |*| "" }
    @provider.define_singleton_method(:analyze_meeting_content) { |*, **| response_data.to_json }
    @retrieval = Object.new
    @retrieval.define_singleton_method(:retrieve_context) { |*| [] }
    @retrieval.define_singleton_method(:format_context) { |*| "" }
    summary_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    @summary = @meeting.meeting_summaries.sole
    assert_equal [ @document.id ], @summary.generation_data.fetch("source_catalog").map { |source| source.fetch("document_id") }
    @topic = Topic.create!(name: @items.first.title, status: "approved", resident_impact_score: 4)
    @items.first.topics << @topic
    assert_equal 1, @topic.topic_appearances.count
  end

  def download_summary_source(text)
    URI.stub(:open, ->(*) { StringIO.new(text) }) { Documents::DownloadJob.perform_now(@document.id) }
  end

  def summary_providers(&block)
    Ai::OpenAiService.stub(:new, @provider) { RetrievalService.stub(:new, @retrieval, &block) }
  end

  def without_summary_providers(&block)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Withdrawn analysis must not dispatch AI" }) do
      RetrievalService.stub(:new, ->(*) { flunk "Withdrawn analysis must not request embeddings" }, &block)
    end
  end

  def clean_summary_withdrawal_scenario
    AuditEvent.where(subject_type: "MeetingSummary", subject_id: @meeting&.meeting_summaries&.select(:id)).delete_all if @meeting
    @topic&.destroy!
    @meeting&.knowledge_sources&.destroy_all
    versions = MeetingDocumentVersion.where(original_meeting_id: @meeting&.id).to_a
    text_versions = MeetingDocumentTextVersion.where(meeting_document_version_id: versions.map(&:id)).to_a
    @meeting&.destroy!
    text_versions.each(&:destroy!)
    versions.each(&:destroy!)
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end
end
