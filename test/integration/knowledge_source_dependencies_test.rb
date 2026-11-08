require "test_helper"
require "timeout"
require_relative "../support/meeting_summary_withdrawal_scenario"

class KnowledgeSourceDependenciesTest < ActionDispatch::IntegrationTest
  include MeetingSummaryWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  RAW_CLAIM = "Rawknowledgeevidenceprobe".freeze
  LAST_CLAIM = "Finalrawknowledgepassage".freeze

  setup do
    @knowledge = []
    build_summary_withdrawal_scenario
    @raw_document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/knowledge-minutes.pdf")
    @raw_text = "#{RAW_CLAIM} first synthetic action. #{LAST_CLAIM} separate synthetic action."
    download_raw_source(@raw_text)
    Documents::PublishText.new(@raw_document.reload).call(raw_pages: [ @raw_text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    @inputs = []
    inputs, topic_name = @inputs, @topic.name
    @provider.define_singleton_method(:extract_knowledge) do |**arguments|
      inputs << arguments
      [ RAW_CLAIM, LAST_CLAIM ].map do |claim|
        { title: claim, body: "#{claim} synthetic knowledge", confidence: 0.9,
          reasoning: "Synthetic raw source support", topic_names: [ topic_name ] }
      end.to_json
    end
    @provider.define_singleton_method(:triage_knowledge) do |entries_json:, **|
      { decisions: JSON.parse(entries_json).map { |entry| { knowledge_source_id: entry.fetch("id"), action: "approve" } } }.to_json
    end
    @embedding = Object.new
    @embedding.define_singleton_method(:embed) { |_| [ 1.0, 0.0, 0.0 ] }
    @actor = User.create!(email_address: "synthetic-knowledge-source-reader@example.test", status: "active", admin: true)
    clear_enqueued_jobs
  end

  teardown do
    AuditEvent.where(subject_type: "KnowledgeSource", subject_id: @knowledge.map(&:id)).delete_all
    @independent&.destroy!
    [ Session, PasskeyCredential, KnownContext ].each { |model| model.where(user_id: @actor&.id).delete_all }
    @meeting&.reload
    clean_summary_withdrawal_scenario
    @actor&.delete
  end

  test "changing additional raw evidence withdraws knowledge while the independent summary and manual context survive" do
    extract_knowledge(triage: true)
    assert_equal @raw_text, @inputs.sole.fetch(:raw_text)
    assert_equal [ @raw_document.id ], @knowledge.first.source_catalog.map { |source| source.fetch("document_id") }
    assert_equal @raw_document.current_text_version.id, @knowledge.first.source_catalog.sole.fetch("text_version_id")
    @independent = KnowledgeSource.create!(title: "Independent synthetic context", body: "Independentknowledgeprobe",
      source_type: "note", status: "approved", active: true)
    Ai::EmbeddingService.stub(:new, @embedding) do
      (@knowledge + [ @independent ]).each { |source| IngestKnowledgeSourceJob.perform_now(source.id) }
    end
    before = @knowledge.map { |source| source.reload.attributes }
    summary_before = @summary.reload.attributes
    sign_in_as_admin(@actor)
    search_context
    assert_includes response.body, RAW_CLAIM
    assert_includes response.body, LAST_CLAIM
    assert_includes response.body, @independent.body
    clear_enqueued_jobs

    without_summary_providers { download_raw_source("Synthetic replacement minutes awaiting extraction") }

    search_context
    refute_includes response.body, RAW_CLAIM
    refute_includes response.body, LAST_CLAIM
    assert_includes response.body, @independent.body
    assert_equal summary_before, @summary.reload.attributes
    @knowledge.each_with_index do |source, index|
      assert_not_nil source.reload.evidence_withdrawn_at
      assert_equal before[index].except("updated_at", "evidence_withdrawn_at"), source.attributes.except("updated_at", "evidence_withdrawn_at")
      assert_equal 1, source.knowledge_chunks.count
      audit = AuditEvent.where(subject: source, action: "knowledge_source.evidence_withdrawn").sole
      assert_equal "source_changed", audit.metadata.fetch("reason")
      assert_equal source.source_catalog, audit.metadata.fetch("source_catalog")
    end
    assert_enqueued_jobs 0, only: [ ExtractKnowledgeJob, AutoTriageKnowledgeJob, IngestKnowledgeSourceJob ]
    assert_enqueued_jobs 1, only: Documents::AnalyzePdfJob

    source = @knowledge.first
    receipt = source.source_catalog
    patch admin_knowledge_source_path(source), params: { knowledge_source: { title: source.title,
      source_catalog: [], evidence_withdrawn_at: nil } }
    assert_redirected_to admin_knowledge_source_path(source)
    assert_equal receipt, source.reload.source_catalog
    assert_not source.available?
    get admin_knowledge_source_path(source)
    assert_response :success
    assert_includes response.body, "Evidence withdrawn"
  end

  test "unchanged failed and unrelated sources preserve available knowledge and queue no extraction" do
    extract_knowledge
    before = @knowledge.map(&:attributes)
    text_version = @raw_document.current_text_version
    clear_enqueued_jobs
    without_summary_providers do
      download_raw_source(@raw_text)
      assert_not Documents::PublishText.new(@raw_document.reload).call(raw_pages: [ @raw_text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
      URI.stub(:open, ->(*) { raise IOError, "Synthetic unavailable source" }) { Documents::DownloadJob.perform_now(@raw_document.id) }
      unrelated = @meeting.meeting_documents.create!(document_type: "transcript", source_url: "https://example.test/unused-transcript", extracted_text: "Synthetic unrelated text")
      unrelated.update!(extracted_text: "Synthetic revised unrelated text")
    end
    assert_equal before, @knowledge.map { |source| source.reload.attributes }
    assert_equal text_version.id, @raw_document.reload.current_text_version.id
    assert_equal 1, @raw_document.source_versions.count
    assert_empty AuditEvent.where(subject: @knowledge)
    assert_enqueued_jobs 0
  end

  test "source removal retains the original receipt and bytes without substituting a new document at its URL" do
    extract_knowledge
    receipts = @knowledge.map(&:source_catalog)
    retained = @raw_document.current_source_version
    old_id, old_url = @raw_document.id, @raw_document.source_url
    @independent = KnowledgeSource.create!(title: "Synthetic legacy extraction", body: "Synthetic legacy text",
      source_type: "note", origin: "extracted", reasoning: "Unknown original provenance", status: "approved")
    assert @knowledge.all?(&:available?)
    assert_predicate @independent, :available?
    without_summary_providers { @raw_document.destroy! }
    assert @knowledge.all? { |source| !source.reload.available? }
    assert_equal receipts, @knowledge.map(&:source_catalog)
    assert_equal @raw_text, retained.reload.file.download
    assert_nil retained.meeting_document_id
    assert_predicate @summary.reload, :published?
    assert_predicate @independent.reload, :available?
    @knowledge.each do |source|
      audit = AuditEvent.where(subject: source, action: "knowledge_source.evidence_withdrawn").sole
      assert_equal "source_unavailable", audit.metadata.fetch("reason")
      assert_equal old_id, audit.metadata.fetch("document_id")
    end
    replacement = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: old_url, extracted_text: @raw_text)
    refute_equal old_id, replacement.id
    assert @knowledge.all? { |source| !source.reload.available? }
    assert_equal receipts, @knowledge.map(&:source_catalog)
  end

  test "late knowledge output cannot publish after its additional document changes" do
    original = @provider.method(:extract_knowledge)
    change = -> { download_raw_source("Synthetic changed minutes during extraction") }
    @provider.define_singleton_method(:extract_knowledge) do |**arguments|
      response = original.call(**arguments)
      change.call
      response
    end
    extract_knowledge(expected_count: nil)
    assert_empty @knowledge
    assert_equal 1, @inputs.size
    assert_predicate @summary.reload, :published?
    assert_enqueued_jobs 0, only: [ AutoTriageKnowledgeJob, IngestKnowledgeSourceJob ]
  end

  test "replacement bytes defer extraction until their own text version is ready" do
    download_raw_source("Synthetic replacement artifact")
    assert_equal @raw_text, @raw_document.reload.extracted_text
    assert_nil @raw_document.current_text_version
    assert_predicate @summary.reload, :published?
    without_summary_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    assert_empty @inputs
    assert_empty KnowledgeSource.where(meeting: @meeting)

    text = "#{RAW_CLAIM} corrected source. #{LAST_CLAIM} corrected final passage."
    publish_raw_text(text, version: "synthetic_v2")
    extract_knowledge
    assert_equal text, @inputs.sole.fetch(:raw_text)
    assert_equal @raw_document.reload.current_text_version.id, @knowledge.first.source_catalog.sole.fetch("text_version_id")
  end

  test "an identical text payload from a different extraction version has a distinct dependency" do
    extract_knowledge
    old_receipts = @knowledge.map(&:source_catalog)
    publish_raw_text(@raw_text, version: "synthetic_v2")
    assert @knowledge.all? { |source| !source.reload.available? }
    assert_equal old_receipts, @knowledge.map(&:source_catalog)
    refute_equal old_receipts.first.sole.fetch("text_version_id"), @raw_document.reload.current_text_version.id
    assert_predicate @summary.reload, :published?
  end

  test "failed dependency audit rolls back text publication and retry withdraws dependents once" do
    extract_knowledge
    before = @knowledge.map(&:attributes)
    document_before = @raw_document.reload.attributes
    record = AuditEvent.method(:record!)
    failing = lambda do |**arguments|
      raise "Synthetic raw knowledge audit failure" if arguments[:action] == "knowledge_source.evidence_withdrawn"
      record.call(**arguments)
    end
    assert_no_difference "MeetingDocumentTextVersion.count" do
      assert_raises(RuntimeError) do
        AuditEvent.stub(:record!, failing) { publish_raw_text("Synthetic corrected text", version: "synthetic_v2") }
      end
    end
    assert_equal document_before, @raw_document.reload.attributes
    assert_equal before, @knowledge.map { |source| source.reload.attributes }
    assert_empty AuditEvent.where(subject: @knowledge)
    publish_raw_text("Synthetic corrected text", version: "synthetic_v2")
    assert @knowledge.all? { |source| !source.reload.available? }
    assert_equal 2, AuditEvent.where(subject: @knowledge, action: "knowledge_source.evidence_withdrawn").count
  end

  test "a changed source URL withdraws knowledge without treating identical retained bytes as new evidence" do
    extract_knowledge
    receipts = @knowledge.map(&:source_catalog)
    bytes = @raw_document.file.download
    without_summary_providers { @raw_document.update!(source_url: "https://example.test/different-minutes.pdf") }
    assert_equal bytes, @raw_document.file.download
    assert @knowledge.all? { |source| !source.reload.available? }
    assert_equal receipts, @knowledge.map(&:source_catalog)
    assert_predicate @summary.reload, :published?
    calls = @inputs.size
    without_summary_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    assert_equal calls, @inputs.size
  end

  test "legacy unversioned text remains identifiable without inventing an archived extraction" do
    @raw_document.destroy!
    @raw_document = @meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://example.test/legacy-minutes.pdf", extracted_text: @raw_text)
    extract_knowledge
    receipt = @knowledge.first.source_catalog.sole
    assert_equal @raw_document.id, receipt.fetch("document_id")
    assert_nil receipt.fetch("text_version_id")
    assert_nil receipt.fetch("artifact_sha256")
    assert_equal 0, @raw_document.source_versions.count
    assert @knowledge.all?(&:available?)
    without_summary_providers { @raw_document.update!(extracted_text: "Synthetic corrected legacy text") }
    assert @knowledge.all? { |source| !source.reload.available? }
  end

  test "summary only extraction records that no additional document was consumed" do
    @raw_document.destroy!
    extract_knowledge
    assert_equal "", @inputs.sole.fetch(:raw_text)
    assert @knowledge.all? { |source| source.source_catalog == [] && source.available? }
    assert_equal [ @summary.id ], @knowledge.map(&:source_summary_id).uniq
  end

  test "unpublished text cannot borrow the retained extraction identity" do
    extract_knowledge
    retained_text = @raw_document.current_text_version
    @raw_document.update!(extracted_text: "Synthetic text edited outside retained extraction publication")
    assert_equal retained_text.id, @raw_document.reload.current_text_version.id
    refute_equal retained_text.extracted_text, @raw_document.extracted_text
    without_summary_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    assert_equal 1, @inputs.size
    assert_equal 2, KnowledgeSource.where(meeting: @meeting).count
    assert @knowledge.all? { |source| !source.reload.available? }
  end

  test "a changed attachment cannot borrow the retained text and artifact identity" do
    extract_knowledge
    retained_text = @raw_document.current_text_version
    @raw_document.file.attach(io: StringIO.new("Synthetic separately replaced attachment"), filename: "replacement.pdf")
    assert_equal retained_text.id, @raw_document.reload.current_text_version.id
    refute_equal retained_text.meeting_document_version.file.blob.checksum, @raw_document.file.blob.checksum
    without_summary_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    assert_equal 1, @inputs.size
    assert_equal 2, KnowledgeSource.where(meeting: @meeting).count
    assert @knowledge.all? { |source| !source.reload.available? }
  end

  test "first knowledge registration and concurrent raw document replacement serialize without missing dependents" do
    paused, release, writer_pid = Queue.new, Queue.new, Queue.new
    meeting_id, document_id = @meeting.id, @raw_document.id
    callback = -> do
      if self.meeting_id == meeting_id && title == RAW_CLAIM
        paused << true
        release.pop
      end
    end
    KnowledgeSource.set_callback(:create, :before, callback)
    producer = writer = nil
    summary_providers do
      producer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { ExtractKnowledgeJob.perform_now(meeting_id) }
      end
      Timeout.timeout(10) { paused.pop }
      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          writer_pid << connection.select_value("SELECT pg_backend_pid()")
          Documents::PublishText.new(MeetingDocument.find(document_id)).call(raw_pages: [ "Synthetic concurrent text revision" ],
            page_count: 1, quality: "text", extractor_version: "synthetic_v2")
        end
      end
      pid = Timeout.timeout(10) { writer_pid.pop }
      waiting = nil
      Timeout.timeout(10) do
        while writer.alive?
          waiting = ActiveRecord::Base.uncached do
            ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
          end
          break if waiting == "Lock"
          sleep 0.01
        end
      end
      assert_equal "Lock", waiting, "Raw-source withdrawal must wait for the first knowledge registration"
      release << true
      assert producer.join(10), "Knowledge publication must finish"
      assert writer.join(10), "Text publication must finish"
      producer.value
      writer.value
    end
    @knowledge = KnowledgeSource.where(meeting: @meeting).order(:id).to_a
    assert_equal 2, @knowledge.size
    assert @knowledge.none?(&:available?)
    assert_equal 2, AuditEvent.where(subject: @knowledge, action: "knowledge_source.evidence_withdrawn").count
    assert_predicate @summary.reload, :published?
    assert_enqueued_jobs 0, only: ExtractKnowledgeJob
  ensure
    KnowledgeSource.skip_callback(:create, :before, callback) if callback
    release << true if release
    producer&.join(10)
    writer&.join(10)
    @knowledge |= KnowledgeSource.where(meeting: @meeting).to_a
  end

  private

  def extract_knowledge(triage: false, expected_count: 2)
    summary_providers do
      ExtractKnowledgeJob.perform_now(@meeting.id)
      AutoTriageKnowledgeJob.perform_now if triage
    end
    @knowledge = KnowledgeSource.where(meeting: @meeting).order(:id).to_a
    assert_equal expected_count, @knowledge.size unless expected_count.nil?
  end

  def publish_raw_text(text, version:)
    without_summary_providers do
      Documents::PublishText.new(@raw_document.reload).call(raw_pages: [ text ], page_count: 1, quality: "text", extractor_version: version)
    end
  end

  def download_raw_source(text)
    URI.stub(:open, ->(*) { StringIO.new(text) }) { Documents::DownloadJob.perform_now(@raw_document.id) }
  end

  def search_context
    Ai::EmbeddingService.stub(:new, @embedding) do
      get admin_search_path, params: { q: "Synthetic knowledge" }
      assert_response :success
    end
  end
end
