require "test_helper"
require "timeout"
require_relative "../support/briefing_withdrawal_scenario"

class KnowledgeSummaryDependenciesTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @knowledge = []
    build_withdrawal_scenario
    @meeting.meeting_documents.create!(document_type: "agenda_pdf",
      source_url: "https://example.test/knowledge-agenda.pdf", extracted_text: "#{@topic.name}. #{@other.name}.")
    @retrieval.define_singleton_method(:retrieve_context) { |*| [] }
    @retrieval.define_singleton_method(:format_context) { |*| "" }
    @provider.define_singleton_method(:prepare_kb_context) { |*| "" }
    @provider.define_singleton_method(:analyze_meeting_content) do |*, **|
      { headline: CLAIM, highlights: [], public_input: [], item_details: [] }.to_json
    end
    names = [ @topic.name, @other.name ]
    @provider.define_singleton_method(:extract_knowledge) do |**|
      names.map.with_index do |name, index|
        { title: "Synthetic generated knowledge #{index}", body: "#{CLAIM} retained knowledge #{index}",
          reasoning: "Synthetic meeting evidence #{index}", confidence: 0.9, topic_names: [ name ] }
      end.to_json
    end
    @provider.define_singleton_method(:triage_knowledge) do |entries_json:, **|
      { decisions: JSON.parse(entries_json).map { |entry| { knowledge_source_id: entry.fetch("id"), action: "approve" } } }.to_json
    end
    @embedding = Object.new
    @embedding.define_singleton_method(:embed) { |_| [ 1.0, 0.0, 0.0 ] }
    withdrawal_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    @summary = @meeting.meeting_summaries.sole
    clear_enqueued_jobs
  end

  teardown do
    @knowledge.each do |source|
      AuditEvent.where(subject_type: "KnowledgeSource", subject_id: source.id).delete_all
      source.destroy! if KnowledgeSource.exists?(source.id)
    end
    AuditEvent.where(subject_type: "MeetingSummary", subject_id: @summary&.id).delete_all
    @session&.destroy!
    @actor&.passkey_credentials&.delete_all
    clean_withdrawal_scenario
  end

  test "a corrected summary withdraws its extracted knowledge from later retrieval while retaining review history" do
    extract_knowledge
    withdrawal_providers { AutoTriageKnowledgeJob.perform_now }
    manual = add_independent_knowledge("Synthetic independent manual context")
    legacy = add_independent_knowledge("Synthetic legacy context", origin: "extracted")
    ingest_knowledge
    assert_equal @knowledge.map(&:id).sort, retrieved_ids
    @session = sign_in_as_admin(@actor)
    Ai::EmbeddingService.stub(:new, @embedding) do
      get admin_search_path, params: { q: "Synthetic knowledge" }
      assert_response :success
      assert_includes response.body, CLAIM
    end
    assert_equal 2, @derived.size
    assert_equal [ [ @topic.id ], [ @other.id ] ], @derived.map { |source| source.topics.pluck(:id) }
    original = @derived.map { |source| source.reload.attributes }
    chunks = KnowledgeChunk.where(knowledge_source: @derived).order(:id).map(&:attributes)
    clear_enqueued_jobs

    without_paid_providers { withdraw_decision }

    assert_equal [ manual.id, legacy.id ].sort, retrieved_ids
    @derived.each_with_index do |source, index|
      assert_not_nil source.reload.evidence_withdrawn_at
      assert_equal original[index].except("updated_at", "evidence_withdrawn_at"), source.attributes.except("updated_at", "evidence_withdrawn_at")
      assert_equal @summary.id, source.source_summary_manifest.fetch("summary_id")
      audit = AuditEvent.where(subject: source, action: "knowledge_source.evidence_withdrawn").sole
      assert_equal "Automated", audit.actor_label
      assert_nil audit.metadata.fetch("current_summary_manifest")
    end
    assert_equal chunks, KnowledgeChunk.where(knowledge_source: @derived).order(:id).map(&:attributes)
    assert_enqueued_jobs 0
    Ai::EmbeddingService.stub(:new, @embedding) do
      get admin_search_path, params: { q: "Synthetic knowledge" }
      assert_response :success
      refute_includes response.body, CLAIM
      assert_includes response.body, manual.body
    end
  end

  test "replacing the supporting summary withdraws old knowledge without inheriting it into a new extraction" do
    extract_knowledge
    previous = @derived
    original = previous.map { |source| source.source_summary_manifest }
    @provider.define_singleton_method(:analyze_meeting_content) do |*, **|
      { headline: "Synthetic corrected preview", highlights: [], public_input: [], item_details: [] }.to_json
    end
    withdrawal_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
    assert previous.all? { |source| !source.reload.available? }
    assert_equal original, previous.map(&:source_summary_manifest)
    assert_equal @summary.id, @meeting.meeting_summaries.sole.id

    withdrawal_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    fresh = KnowledgeSource.where(meeting: @meeting).where.not(id: previous.map(&:id)).order(:id).to_a
    @knowledge.concat(fresh)
    assert_equal 2, fresh.size
    assert fresh.all?(&:available?)
    assert fresh.all? { |source| source.status == "proposed" }
    refute_equal original.first.fetch("payload_sha256"), fresh.first.source_summary_manifest.fetch("payload_sha256")
    before = fresh.map(&:attributes)
    @summary.reload.update!(generation_data: @summary.generation_data)
    assert_equal before, fresh.map { |source| source.reload.attributes }
    assert previous.all? { |source| !source.reload.available? }
  end

  test "summary removal retains knowledge its original summary identity and its withdrawal audit" do
    extract_knowledge
    receipt = @derived.first.source_summary_manifest
    without_paid_providers { @summary.destroy! }
    assert @derived.all? { |source| !source.reload.available? && source.source_summary_id.nil? }
    assert_equal receipt, @derived.first.source_summary_manifest
    assert_equal @summary.id, receipt.fetch("summary_id")
    assert_equal "summary_removed", AuditEvent.where(subject: @derived.first, action: "knowledge_source.evidence_withdrawn").sole.metadata.fetch("reason")
    assert_equal 2, KnowledgeSource.where(meeting: @meeting).count
  end

  test "summary timestamps and JSON ordering preserve compatible knowledge without more work" do
    extract_knowledge
    before = @derived.map(&:attributes)
    receipt = @derived.first.source_summary_manifest
    assert_equal receipt, Knowledge::SummaryEvidence.capture(@summary.reload)
    clear_enqueued_jobs
    without_paid_providers do
      @summary.touch
      @summary.update!(generation_data: @summary.generation_data.to_a.reverse.to_h)
    end
    assert_equal before, @derived.map { |source| source.reload.attributes }
    assert_equal receipt, Knowledge::SummaryEvidence.capture(@summary.reload)
    assert_empty AuditEvent.where(subject: @derived, action: "knowledge_source.evidence_withdrawn")
    assert_enqueued_jobs 0
  end

  test "failed knowledge withdrawal audit rolls back the originating correction and a retry withdraws once" do
    extract_knowledge
    original = @derived.map(&:attributes)
    record = AuditEvent.method(:record!)
    failing_audit = lambda do |**attributes|
      raise "Synthetic knowledge audit failure" if attributes[:action] == "knowledge_source.evidence_withdrawn"
      record.call(**attributes)
    end
    assert_no_difference "CouncilDecisionCorrection.count" do
      assert_raises(RuntimeError) do
        AuditEvent.stub(:record!, failing_audit) { without_paid_providers { withdraw_decision } }
      end
    end
    assert_predicate @summary.reload, :published?
    assert_nil @briefing.reload.evidence_withdrawn_at
    assert_equal original, @derived.map { |source| source.reload.attributes }
    assert_empty AuditEvent.where(subject: @derived, action: "knowledge_source.evidence_withdrawn")
    without_paid_providers { withdraw_decision }
    assert @derived.all? { |source| !source.reload.available? }
    assert_equal 2, AuditEvent.where(subject: @derived, action: "knowledge_source.evidence_withdrawn").count
  end

  test "a late triage response cannot approve withdrawn entries and queued triage makes no provider calls" do
    travel_to Time.current.change(usec: 0) do
      extract_knowledge
      response = @provider.method(:triage_knowledge)
      correct = -> { withdraw_decision }
      @provider.define_singleton_method(:triage_knowledge) do |**arguments|
        result = response.call(**arguments)
        correct.call
        result
      end
      withdrawal_providers { AutoTriageKnowledgeJob.perform_now }
      assert @derived.all? { |source| source.reload.status == "proposed" && !source.available? }
      without_paid_providers { AutoTriageKnowledgeJob.perform_now }
    end
  end

  test "topic generation receipts exclude withdrawn knowledge inputs" do
    extract_knowledge
    withdrawal_providers { AutoTriageKnowledgeJob.perform_now }
    ingest_knowledge
    refs = lambda do
      Ai::EmbeddingService.stub(:new, @embedding) do
        Topics::GenerationEvidence.summary_inputs(@topic.id, @meeting.id).fetch(:evidence).fetch("knowledge_evidence")
      end
    end
    assert_equal 1, refs.call.size
    without_paid_providers { withdraw_decision }
    assert_empty refs.call
  end

  test "late embedding output cannot replace retained chunks after withdrawal and queued ingestion makes no calls" do
    extract_knowledge
    ingest_knowledge
    source = @derived.first
    before = source.knowledge_chunks.order(:id).map(&:attributes)
    correct = -> { withdraw_decision }
    @embedding.define_singleton_method(:embed) do |_|
      correct.call
      [ 0.0, 1.0, 0.0 ]
    end
    Ai::EmbeddingService.stub(:new, @embedding) { IngestKnowledgeSourceJob.perform_now(source.id) }
    assert_not source.reload.available?
    assert_equal before, source.knowledge_chunks.order(:id).map(&:attributes)
    Ai::EmbeddingService.stub(:new, ->(*) { flunk "Withdrawn ingestion must not request embeddings" }) do
      @derived.each { |entry| IngestKnowledgeSourceJob.perform_now(entry.id) }
    end
  end

  test "admin editing approval and reingestion do not silently restore withdrawn evidence" do
    extract_knowledge
    source = @derived.first
    receipt = source.source_summary_manifest
    @session = sign_in_as_admin(@actor)
    get admin_knowledge_source_path(source)
    assert_response :success
    assert_includes response.body, source.body
    refute_includes response.body, "Evidence withdrawn"
    without_paid_providers { withdraw_decision }
    clear_enqueued_jobs

    without_paid_providers do
      get admin_knowledge_source_path(source)
      assert_response :success
      assert_includes response.body, "Evidence withdrawn"
      assert_includes response.body, "retained for review but excluded from AI context"
      post reingest_admin_knowledge_source_path(source)
      assert_redirected_to admin_knowledge_source_path(source)
      assert_equal "Supporting evidence was withdrawn. Re-ingestion was not queued.", flash[:alert]
      patch admin_knowledge_source_path(source), params: { knowledge_source: {
        body: "Synthetic edited background", status: "approved", active: true,
        evidence_withdrawn_at: nil, source_summary_manifest: {}, source_summary_id: nil
      } }
      assert_redirected_to admin_knowledge_source_path(source)
      assert_equal "Knowledge source updated. Supporting evidence remains withdrawn.", flash[:notice]
      assert_equal "manual", source.reload.origin
      assert_equal "approved", source.status
      assert_not source.available?
      assert_equal receipt, source.source_summary_manifest
      assert_equal @summary.id, source.source_summary_id
      assert_enqueued_jobs 0
    end
  end

  test "late embeddings cannot overwrite a completed ingestion of edited content" do
    extract_knowledge
    source = @derived.first
    ingest_knowledge
    updated_chunks = nil
    changed = false
    @embedding.define_singleton_method(:embed) do |_|
      unless changed
        changed = true
        source.update!(body: "Synthetic replacement knowledge")
        IngestKnowledgeSourceJob.perform_now(source.id)
        updated_chunks = source.knowledge_chunks.order(:id).map(&:attributes)
      end
      [ 0.0, 1.0, 0.0 ]
    end
    Ai::EmbeddingService.stub(:new, @embedding) { IngestKnowledgeSourceJob.perform_now(source.id) }
    assert_equal updated_chunks, source.knowledge_chunks.order(:id).map(&:attributes)
    assert_equal [ "Synthetic replacement knowledge" ], source.knowledge_chunks.pluck(:content)
  end

  test "an embedding failure preserves the whole previous index until a successful retry" do
    extract_knowledge
    source = @derived.first
    ingest_knowledge
    before = source.knowledge_chunks.order(:id).map(&:attributes)
    source.update!(body: ("Synthetic expanded context. " * 90) + "Distinctive final evidence.")
    calls = 0
    @embedding.define_singleton_method(:embed) do |_|
      calls += 1
      raise "Synthetic embedding failure" if calls == 2
      [ 1.0, 0.0, 0.0 ]
    end
    assert_raises(RuntimeError) do
      Ai::EmbeddingService.stub(:new, @embedding) { IngestKnowledgeSourceJob.perform_now(source.id) }
    end
    assert_equal before, source.knowledge_chunks.order(:id).map(&:attributes)
    assert_equal 2, calls
    Ai::EmbeddingService.stub(:new, @embedding) { IngestKnowledgeSourceJob.perform_now(source.id) }
    assert_equal 2, source.knowledge_chunks.count
    assert_includes source.knowledge_chunks.order(:chunk_index).last.content, "Distinctive final evidence."
    refute_equal before.map { |chunk| chunk.fetch("id") }, source.knowledge_chunks.order(:id).pluck(:id)
  end

  test "late triage cannot approve an edited entry even when its timestamp is unchanged" do
    travel_to Time.current.change(usec: 0) do
      extract_knowledge
      source = @derived.first
      response = @provider.method(:triage_knowledge)
      @provider.define_singleton_method(:triage_knowledge) do |**arguments|
        result = response.call(**arguments)
        source.update!(body: "Synthetic replacement awaiting its own review")
        result
      end
      withdrawal_providers { AutoTriageKnowledgeJob.perform_now }
      assert_equal "proposed", source.reload.status
      assert_equal "Synthetic replacement awaiting its own review", source.body
      assert_equal "approved", @derived.last.reload.status
    end
  end

  test "pattern extraction excludes withdrawn knowledge inactive notes and withdrawn briefings" do
    extract_knowledge
    withdrawal_providers { AutoTriageKnowledgeJob.perform_now }
    manual = add_independent_knowledge("Synthetic supported pattern input")
    inactive = add_independent_knowledge("Synthetic inactive pattern input")
    inactive.update!(active: false)
    without_paid_providers { withdraw_decision }
    captured = []
    @provider.define_singleton_method(:extract_knowledge_patterns) do |**arguments|
      captured << arguments
      "[]"
    end
    withdrawal_providers { ExtractKnowledgePatternsJob.perform_now }
    assert_equal 1, captured.size
    assert_includes captured.sole.fetch(:knowledge_entries), manual.body
    refute_includes captured.sole.fetch(:knowledge_entries), inactive.body
    refute_includes captured.sole.fetch(:knowledge_entries), CLAIM
    refute_includes captured.sole.fetch(:recent_summaries), CLAIM
    assert_includes captured.sole.fetch(:recent_summaries), @other_briefing.headline
    manual.update!(active: false)
    without_paid_providers { ExtractKnowledgePatternsJob.perform_now }
  end

  test "first knowledge publication and concurrent summary withdrawal serialize without missing dependents" do
    paused, release, writer_pid = Queue.new, Queue.new, Queue.new
    meeting_id = @meeting.id
    callback = -> do
      if self.meeting_id == meeting_id && title == "Synthetic generated knowledge 0"
        paused << true
        release.pop
      end
    end
    KnowledgeSource.set_callback(:create, :before, callback)
    producer = writer = nil
    withdrawal_providers do
      producer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { ExtractKnowledgeJob.perform_now(meeting_id) }
      end
      Timeout.timeout(10) { paused.pop }
      writer = Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          writer_pid << connection.select_value("SELECT pg_backend_pid()")
          MeetingSummary.find(@summary.id).update!(evidence_withdrawn_at: Time.current)
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
      assert_equal "Lock", waiting, "Withdrawal must wait for the first knowledge registration"
      release << true
      assert producer.join(10), "Knowledge publication must finish"
      assert writer.join(10), "Withdrawal must finish"
      producer.value
      writer.value
    end
    @derived = KnowledgeSource.where(meeting: @meeting).order(:id).to_a
    @knowledge.concat(@derived)
    assert_equal 2, @derived.size
    assert @derived.none?(&:available?)
    assert_equal 2, AuditEvent.where(subject: @derived, action: "knowledge_source.evidence_withdrawn").count
    assert_enqueued_jobs 0, only: ExtractKnowledgeJob
  ensure
    KnowledgeSource.skip_callback(:create, :before, callback) if callback
    release << true if release
    producer&.join(10)
    writer&.join(10)
    @knowledge |= KnowledgeSource.where(meeting: @meeting).to_a
  end

  private

  def extract_knowledge
    withdrawal_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    @derived = KnowledgeSource.where(meeting: @meeting).order(:id).to_a
    @knowledge.concat(@derived)
  end

  def add_independent_knowledge(body, origin: "manual")
    KnowledgeSource.create!(title: body, body: body, source_type: "note", status: "approved", active: true,
      origin: origin, reasoning: "Synthetic independent evidence").tap { |source| @knowledge << source }
  end

  def ingest_knowledge
    Ai::EmbeddingService.stub(:new, @embedding) do
      @knowledge.each { |source| IngestKnowledgeSourceJob.perform_now(source.id) }
    end
  end

  def retrieved_ids
    Ai::EmbeddingService.stub(:new, @embedding) do
      RetrievalService.new.retrieve_context("Synthetic knowledge").map { |entry| entry.fetch(:chunk).knowledge_source_id }.sort
    end
  end
end
