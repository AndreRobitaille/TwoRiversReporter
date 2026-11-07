require "test_helper"
require_relative "../support/meeting_summary_withdrawal_scenario"

class MeetingSummarySourceWithdrawalTest < ActionDispatch::IntegrationTest
  include MeetingSummaryWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @previous_setting = SiteSetting.first
    @previous_mode = @previous_setting&.access_mode
    SiteSetting.instance.update!(access_mode: "open")
    build_summary_withdrawal_scenario
    @actor = User.create!(email_address: "synthetic-summary-reader@example.test", status: "active", admin: true)
    _, secret = ApiAccessToken.issue!(user: @actor, name: "Synthetic summary reader", expires_in: 1.day)
    @bearer = { "Authorization" => "Bearer #{secret}" }
    clear_enqueued_jobs
  end

  teardown do
    [ ApiAccessToken, Session, PasskeyCredential, KnownContext ].each { |model| model.where(user_id: @actor&.id).delete_all }
    AuditEvent.where(actor_id: @actor&.id).delete_all
    clean_summary_withdrawal_scenario
    @actor&.delete
    @previous_setting ? @previous_setting.update!(access_mode: @previous_mode) : SiteSetting.first&.destroy!
  end

  test "changed source withdraws summary and image across later HTML API search and queued consumers" do
    original = @summary.attributes
    image = @meeting.generated_images.create!(status: "ready", purpose: "feature_and_og", source_summary: @summary)
    image.file.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "synthetic.png", content_type: "image/png")
    get meeting_path(@meeting)
    assert_response :success
    assert_includes response.body, CLAIM
    assert_includes response.body, SECOND_CLAIM
    etag = response.headers.fetch("ETag")
    get "/api/v1/meetings/#{@meeting.id}/agenda_items", headers: @bearer
    assert_equal @items.map(&:id), response.parsed_body.fetch("data").map { |item| item.fetch("agenda_item_id") }
    assert_includes response.body, CLAIM
    get "/api/v1/meetings", params: { q: CLAIM }, headers: @bearer
    assert_equal [ @meeting.id ], response.parsed_body.fetch("data").map { |meeting| meeting.fetch("id") }
    since = Time.current
    without_summary_providers do
      travel 2.seconds do
        download_summary_source("Synthetic changed agenda bytes awaiting extraction")
        get meeting_path(@meeting), headers: { "If-None-Match" => etag }
        assert_response :success
        refute_includes response.body, CLAIM
        refute_includes response.body, SECOND_CLAIM
        assert_includes response.body, "supporting evidence changed"
        assert_includes response.body, @document.source_url
        get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
        assert_nil response.parsed_body.dig("data", "summary")
        get "/api/v1/meetings/#{@meeting.id}/agenda_items", headers: @bearer
        assert_equal @items.map(&:id), response.parsed_body.fetch("data").map { |item| item.fetch("agenda_item_id") }
        assert response.parsed_body.fetch("data").none? { |item| item.dig("analysis", "ai_generated") }
        refute_includes response.body, CLAIM
        get "/api/v1/meetings", params: { q: CLAIM }, headers: @bearer
        assert_empty response.parsed_body.fetch("data")
        get "/api/v1/meetings", params: { updated_since: since.iso8601(6) }, headers: @bearer
        assert_equal [ @meeting.id ], response.parsed_body.fetch("data").map { |meeting| meeting.fetch("id") }
        ExtractKnowledgeJob.perform_now(@meeting.id)
        PruneHollowAppearancesJob.perform_now(@meeting.id)
        GeneratedImages::Config.stub(:enabled?, true) { GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id) }
      end
    end
    assert @items.first.topics.exists?(@topic.id)
    assert_equal 1, @topic.topic_appearances.count
    assert_equal original.slice("generation_data", "content"), @summary.reload.attributes.slice("generation_data", "content")
    assert_not_nil @summary.evidence_withdrawn_at
    assert_equal "superseded", image.reload.status
    assert image.file.attached?
    assert_equal 2, @document.reload.source_versions.count
    audit = AuditEvent.where(subject: @summary, action: "meeting_summary.source_withdrawn").sole
    assert_equal "Automated", audit.actor_label
    assert_equal original.fetch("generation_data").fetch("source_catalog"), audit.metadata.fetch("source_catalog")
    sign_in_as(@actor)
    get admin_audit_events_path
    assert_response :success
    assert_select "tbody tr", text: /Automated.*meeting_summary\.source_withdrawn.*Meeting: City Council \(#{@meeting.id}\)/m, count: 1
  end

  test "unchanged and failed sources preserve analysis while a failed audit rolls source replacement back" do
    original = @summary.attributes
    source = Citations::SourceCatalog.snapshot(@document.reload)
    without_summary_providers do
      download_summary_source(@source_text)
      @document.reload.touch
      URI.stub(:open, ->(*) { raise IOError, "Synthetic fetch failure" }) { Documents::DownloadJob.perform_now(@document.id) }
      assert_equal original, @summary.reload.attributes
      AuditEvent.stub(:record!, ->(**) { raise "Synthetic audit persistence failure" }) do
        download_summary_source("Synthetic revised bytes")
      end
    end
    assert_equal source, Citations::SourceCatalog.snapshot(@document.reload)
    assert_equal 1, @document.source_versions.count
    assert_equal original, @summary.reload.attributes
    get meeting_path(@meeting)
    assert_includes response.body, CLAIM
  end

  test "source deletion preserves independent summary and explicit regeneration restores only current evidence" do
    independent = @meeting.meeting_summaries.create!(summary_type: "packet_analysis", generation_data: {
      headline: "Independent synthetic analysis", item_details: [], source_catalog: []
    })
    without_summary_providers { @document.destroy! }
    assert_not @summary.reload.published?
    assert_predicate independent.reload, :published?
    get meeting_path(@meeting)
    assert_includes response.body, "Independent synthetic analysis"
    refute_includes response.body, CLAIM
    assert_equal "source_unavailable", AuditEvent.where(subject: @summary).sole.metadata.fetch("reason")

    @document = @meeting.meeting_documents.create!(document_type: "agenda_pdf", source_url: "https://example.test/replacement-agenda.pdf", extracted_text: @source_text)
    @response_data[:headline] = "Current synthetic preview"
    @response_data[:item_details].each { |item| item[:citations].first[:source_id] = "doc-#{@document.id}" }
    summary_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    assert_predicate @summary.reload, :published?
    assert_equal [ @document.id ], @summary.generation_data.fetch("source_catalog").map { |source| source.fetch("document_id") }
    independent.destroy!
    get meeting_path(@meeting)
    assert_includes response.body, "Current synthetic preview"
    get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
    assert_includes response.body, "Current synthetic preview"
  end

  test "late summary response cannot restore withdrawn evidence or enqueue dependent work" do
    original = @summary.generation_data
    scenario = self
    @provider.define_singleton_method(:analyze_meeting_content) do |*, **|
      scenario.download_summary_source("Synthetic changed bytes during provider call")
      original.merge("headline" => "Stale late summary").to_json
    end
    GeneratedImages::Config.stub(:enabled?, true) do
      summary_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    end
    assert_not @summary.reload.published?
    assert_equal original, @summary.generation_data
    assert_enqueued_jobs 0, only: [ GeneratedImages::GenerateForMeetingJob, Topics::GenerateTopicBriefingJob ]
    get meeting_path(@meeting)
    refute_includes response.body, "Stale late summary"
    refute_includes response.body, CLAIM
  end

  test "late knowledge and image output cannot publish after their summary source changes" do
    knowledge = { entries: [ { title: "Synthetic knowledge", body: "Synthetic", confidence: 0.95, reasoning: "Synthetic source support" } ] }
    @provider.define_singleton_method(:extract_knowledge) { |**| knowledge.to_json }
    summary_providers { assert_difference("KnowledgeSource.count", 1) { ExtractKnowledgeJob.perform_now(@meeting.id) } }
    assert_equal "Synthetic knowledge", @meeting.knowledge_sources.sole.title
    clear_enqueued_jobs
    scenario = self
    @provider.define_singleton_method(:extract_knowledge) do |**|
      scenario.download_summary_source("Synthetic source changed while extracting knowledge")
      knowledge.to_json
    end
    summary_providers do
      assert_no_difference "KnowledgeSource.count" do
        ExtractKnowledgeJob.perform_now(@meeting.id)
      end
    end
    assert_enqueued_jobs 0, only: AutoTriageKnowledgeJob

    # Restore through real text publication and checked summary generation first.
    Documents::PublishText.new(@document.reload).call(raw_pages: [ @source_text ], page_count: 1, quality: "text", extractor_version: "synthetic_v2")
    summary_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    assert_predicate @summary.reload, :published?
    @provider.define_singleton_method(:build_generated_image_brief) { |*| { "civic_issue" => "Synthetic library", "composition" => "Exterior" } }
    image_response = { bytes: "synthetic-image", model: "deterministic", format: "jpeg", size: "1536x1024" }
    @provider.define_singleton_method(:generate_civic_image) { |**| image_response }
    allowed_image = GeneratedImages::Generator.new(@meeting, source: @summary, ai_service: @provider).call
    assert_equal "ready", allowed_image.reload.status
    assert allowed_image.file.attached?
    @provider.define_singleton_method(:generate_civic_image) do |**|
      scenario.download_summary_source("Synthetic source changed during illustration")
      image_response
    end
    image = GeneratedImages::Generator.new(@meeting, source: @summary, ai_service: @provider).call
    assert_equal "superseded", image.reload.status
    assert_not image.file.attached?
    assert_not @summary.reload.published?
  end

  test "a newer checked summary wins over an older in flight response" do
    original = @summary.generation_data
    meeting = @meeting
    @provider.define_singleton_method(:analyze_meeting_content) do |*, **|
      Meetings::SummaryPublication.publish(meeting: meeting, summary_type: "agenda_preview",
        expected: Meetings::SummaryPublication.version(meeting.meeting_summaries.sole), sources: original.fetch("source_catalog")) do
        meeting.meeting_summaries.sole.update!(generation_data: original.merge("headline" => "Newer checked summary"))
      end
      original.merge("headline" => "Late older summary").to_json
    end
    summary_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    assert_equal "Newer checked summary", @summary.reload.generation_data.fetch("headline")
    get meeting_path(@meeting)
    assert_includes response.body, "Newer checked summary"
    refute_includes response.body, "Late older summary"
  end

  test "discarded full recap preserves independent preview and does not start downstream processing" do
    minutes = @meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://example.test/summary-minutes.pdf", extracted_text: "Synthetic original minutes")
    original = @summary.attributes
    response_data = @response_data
    @provider.define_singleton_method(:analyze_meeting_content) do |*, **|
      minutes.update!(extracted_text: "Synthetic corrected minutes")
      response_data.to_json
    end
    publication_error = begin
      summary_providers { SummarizeMeetingJob.perform_now(@meeting.id) }
      nil
    rescue Citations::SourceCatalog::InvalidSource => error
      error.message
    end
    assert_nil publication_error, "A stale response must be discarded before citation validation, without failing the job"
    assert_equal original, @summary.reload.attributes
    assert_equal [ @summary.id ], @meeting.meeting_summaries.pluck(:id)
    assert_enqueued_jobs 0, only: [ PruneHollowAppearancesJob, ExtractKnowledgeJob, Topics::GenerateTopicBriefingJob ]
    get meeting_path(@meeting)
    assert_includes response.body, CLAIM
  end
end
