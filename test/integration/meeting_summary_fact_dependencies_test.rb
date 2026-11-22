require "test_helper"
require "timeout"
require_relative "../support/briefing_withdrawal_scenario"

class MeetingSummaryFactDependenciesTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  OLD_CLAIM = "Syntheticoldvotetotalreport".freeze
  CURRENT_CLAIM = "Syntheticcurrentvotetotalreport".freeze

  setup do
    @previous_setting = SiteSetting.first
    @previous_mode = @previous_setting&.access_mode
    SiteSetting.instance.update!(access_mode: "open")
    @templates = {}
    build_withdrawal_scenario(vote_value: "no")
    @original_publication = @meeting.reload.minutes_publication
    @original_source = Citations::SourceCatalog.snapshot(@document.reload)
    @analysis_inputs = []
    inputs, agenda_id, title = @analysis_inputs, @agenda.id, @agenda.title
    @provider.define_singleton_method(:prepare_kb_context) { |*| "" }
    @provider.define_singleton_method(:analyze_meeting_content) do |*, **options|
      context = options.fetch(:motion_context)
      inputs << context
      claim = context.include?("no=1") ? OLD_CLAIM : CURRENT_CLAIM
      source_id = options.fetch(:source_catalog).first.fetch("source_id")
      { headline: claim, highlights: [], public_input: [], item_details: [ {
        agenda_item_id: agenda_id, agenda_item_title: title, summary: claim,
        citations: [ { source_id: source_id, location: { kind: "whole_source" } } ]
      } ] }.to_json
    end
    @provider.define_singleton_method(:analyze_topic_summary) { |*, **| { factual_record: [] }.to_json }
    @provider.define_singleton_method(:render_topic_summary) { |*, **| "Synthetic related analysis" }
    @retrieval.define_singleton_method(:retrieve_context) { |*, **| [] }
    @retrieval.define_singleton_method(:format_context) { |*| "" }
    generate_summary
    @summary = @meeting.meeting_summaries.sole
    @original_summary = @summary.attributes
    _, secret = ApiAccessToken.issue!(user: @actor, name: "Synthetic summary fact reader", expires_in: 1.day)
    @bearer = { "Authorization" => "Bearer #{secret}" }
    clear_enqueued_jobs
  end

  teardown do
    @templates.each do |key, original|
      template = PromptTemplate.find_by(key: key)
      if original
        template.update_columns(original.fetch(:attributes))
        template.versions.where.not(id: original.fetch(:version_ids)).delete_all
      else
        template&.destroy!
      end
    end
    [ ApiAccessToken, Session, PasskeyCredential, KnownContext ].each { |model| model.where(user_id: @actor&.id).delete_all }
    AuditEvent.where(subject_type: "MeetingSummary", subject_id: @meeting&.meeting_summaries&.select(:id)).delete_all if @meeting
    clean_withdrawal_scenario
    @previous_setting ? @previous_setting.update!(access_mode: @previous_mode) : SiteSetting.first&.destroy!
  end

  test "revised extracted votes withdraw a saved summary while its unchanged source and original facts remain inspectable" do
    image = @meeting.generated_images.create!(status: "ready", purpose: "feature_and_og", source_summary: @summary)
    image.file.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "synthetic.png", content_type: "image/png")
    get meeting_path(@meeting)
    assert_response :success
    assert_includes response.body, OLD_CLAIM
    assert_includes @analysis_inputs.sole, "no=1"
    etag = response.headers.fetch("ETag")
    member = Member.find_by!(name: "Alex Example")
    get member_path(member)
    assert_select ".member-vote-row", count: 1
    assert_select ".vote-value", text: "No", count: 1
    get "/api/v1/meetings", params: { q: OLD_CLAIM }, headers: @bearer
    assert_equal [ @meeting.id ], response.parsed_body.fetch("data").map { |row| row.fetch("id") }

    since = Time.current
    travel 2.seconds do
      refresh_votes
      without_paid_providers do
        get meeting_path(@meeting), headers: { "If-None-Match" => etag }
        assert_response :success
        refute_includes response.body, OLD_CLAIM
        assert_includes response.body, "supporting evidence changed"
        assert_select "a[href='#{@document.source_url}']"
        get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
        assert_nil response.parsed_body.dig("data", "summary")
        get "/api/v1/meetings", params: { q: OLD_CLAIM }, headers: @bearer
        assert_empty response.parsed_body.fetch("data")
        get "/api/v1/meetings", params: { updated_since: since.iso8601(6) }, headers: @bearer
        assert_equal [ @meeting.id ], response.parsed_body.fetch("data").map { |row| row.fetch("id") }
        get member_path(member)
        assert_select ".member-vote-row", count: 1
        assert_select ".vote-value", text: "Yes", count: 1
      end
    end
    assert_equal @original_source, Citations::SourceCatalog.snapshot(@document.reload)
    assert_equal 1, @document.source_versions.count
    assert_equal @original_summary.slice("generation_data", "content"), @summary.reload.attributes.slice("generation_data", "content")
    assert_not @summary.published?
    assert_equal "superseded", image.reload.status
    assert image.file.attached?
    assert_equal "no", @original_publication.votes_extraction.data.fetch("motions").sole.fetch("votes").sole.fetch("value")
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    receipt = @summary.generation_data.fetch("motion_context_manifest")
    assert_equal @original_publication.id, receipt.fetch("publication_id")
    assert_equal @original_publication.votes_extraction_id, receipt.fetch("votes_extraction_id")
    audit = AuditEvent.where(subject: @summary, action: "meeting_summary.facts_withdrawn").sole
    assert_equal "Automated", audit.actor_label
    assert_equal receipt, audit.metadata.fetch("motion_context_manifest")
    assert_equal @meeting.reload.minutes_publication_id, audit.metadata.dig("current_publication", "id")
    assert_enqueued_jobs 0, only: [ SummarizeMeetingJob, GeneratedImages::GenerateForMeetingJob ]
    sign_in_as(@actor)
    get admin_audit_events_path
    assert_response :success
    assert_select "tbody tr", text: /Automated.*meeting_summary\.facts_withdrawn.*Meeting: Synthetic Council \(#{@meeting.id}\)/m, count: 1
  end

  test "unchanged inputs and compatible attendance republication preserve supported summary without generation" do
    without_paid_providers do
      assert_no_enqueued_jobs do
        ExtractVotesJob.perform_now(@meeting.id)
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end
    assert_equal @original_summary, @summary.reload.attributes
    revise_template("attendance")
    withdrawal_providers { ExtractCommitteeMembersJob.perform_now(@meeting.id, refresh: true) }
    assert_not_equal @original_publication.id, @meeting.reload.minutes_publication_id
    assert_equal @original_publication.votes_extraction_id, @meeting.minutes_publication.votes_extraction_id
    assert_equal @original_summary, @summary.reload.attributes
    assert_equal 1, @analysis_inputs.size
    get meeting_path(@meeting)
    assert_includes response.body, OLD_CLAIM
  end

  test "legacy summaries with missing or null receipts keep unknown provenance after fact replacement" do
    data = @summary.generation_data.except("motion_context_manifest")
    @summary.update!(generation_data: data)
    unknown = @meeting.meeting_summaries.create!(summary_type: "agenda_preview", content: @summary.content,
      generation_data: data.merge("motion_context_manifest" => nil))
    before = [ @summary, unknown ].map(&:attributes)
    refresh_votes
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    assert_equal before, [ @summary, unknown ].map { |summary| summary.reload.attributes }
    assert_empty AuditEvent.where(subject: [ @summary, unknown ])
    get meeting_path(@meeting)
    assert_includes response.body, OLD_CLAIM
  end

  test "a new extraction with identical motion context keeps the retained summary and its original receipt" do
    revise_template("votes")
    withdrawal_providers { ExtractVotesJob.perform_now(@meeting.id, refresh: true) }
    assert_not_equal @original_publication.votes_extraction_id, @meeting.reload.minutes_publication.votes_extraction_id
    assert_equal @original_summary, @summary.reload.attributes
    assert_equal 1, @analysis_inputs.size
    assert_empty AuditEvent.where(subject: @summary)
  end

  test "failed summary audit rolls back fact publication and a retry uses completed extraction without AI" do
    original_motion_ids = @meeting.motions.pluck(:id)
    record = AuditEvent.method(:record!)
    AuditEvent.stub(:record!, ->(**args) {
      raise "Synthetic summary audit failure" if args[:action] == "meeting_summary.facts_withdrawn"
      record.call(**args)
    }) do
      assert_raises(RuntimeError) { refresh_votes }
    end
    assert_equal @original_publication.id, @meeting.reload.minutes_publication_id
    assert_equal original_motion_ids, @meeting.motions.pluck(:id)
    assert_equal @original_summary, @summary.reload.attributes
    assert_equal 2, @meeting.minutes_extractions.where(kind: "votes", status: "completed").count
    assert_enqueued_jobs 0, only: Topics::UpdateContinuityJob
    without_paid_providers { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    assert_not @summary.reload.published?
    assert_equal 1, AuditEvent.where(subject: @summary, action: "meeting_summary.facts_withdrawn").count
    without_paid_providers { assert_no_enqueued_jobs { ExtractVotesJob.perform_now(@meeting.id) } }
  end

  test "a fact change during generation cannot publish a first summary or enqueue its followups" do
    @summary.destroy!
    provider = @provider.method(:analyze_meeting_content)
    scenario = self
    @provider.define_singleton_method(:analyze_meeting_content) do |*args, **kwargs|
      result = provider.call(*args, **kwargs)
      scenario.send(:refresh_votes, providers: false)
      result
    end
    GeneratedImages::Config.stub(:enabled?, true) { generate_summary }
    assert_includes @analysis_inputs.last, "no=1"
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    assert_empty @meeting.meeting_summaries
    assert_enqueued_jobs 0, only: [ GeneratedImages::GenerateForMeetingJob, Topics::GenerateTopicBriefingJob ]
    get meeting_path(@meeting)
    refute_includes response.body, OLD_CLAIM
  end

  test "agenda preview pins its structured minutes dependency even when minutes are outside its source catalog" do
    # Isolate the minutes dependency from independently sufficient topic context.
    @topic.update!(resident_impact_score: 2)
    agenda_doc = @meeting.meeting_documents.create!(document_type: "agenda_pdf",
      source_url: "https://example.test/fact-summary-agenda.pdf", extracted_text: "Synthetic cedar improvements")
    generate_summary(mode: :agenda_preview)
    preview = @meeting.meeting_summaries.find_by!(summary_type: "agenda_preview")
    assert_predicate preview, :published?
    assert_equal [ agenda_doc.id ], preview.generation_data.fetch("source_catalog").map { |source| source.fetch("document_id") }
    assert_equal [ @document.id ], preview.generation_data.dig("motion_context_manifest", "source_catalog").map { |source| source.fetch("document_id") }
    assert_equal OLD_CLAIM, preview.generation_data.fetch("headline")
    without_paid_providers do
      URI.stub(:open, ->(*) { StringIO.new("Synthetic replacement minutes") }) { Documents::DownloadJob.perform_now(@document.id) }
    end
    assert_not preview.reload.published?
    assert_not @summary.reload.published?
    audit = AuditEvent.where(subject: preview, action: "meeting_summary.source_withdrawn").sole
    assert_equal preview.generation_data.fetch("motion_context_manifest"), audit.metadata.fetch("motion_context_manifest")
    get meeting_path(@meeting)
    refute_includes response.body, OLD_CLAIM
    assert_select "a[href='#{agenda_doc.source_url}']"
  end

  test "a newly discovered unavailable URL cannot replace the summary's pinned source" do
    without_paid_providers do
      missing = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/unavailable-minutes.pdf")
      URI.stub(:open, ->(*) { raise IOError, "Synthetic unavailable source" }) { Documents::DownloadJob.perform_now(missing.id) }
    end
    assert_equal @original_summary, @summary.reload.attributes
    get meeting_path(@meeting)
    assert_includes response.body, OLD_CLAIM
  end

  test "date reprojection withdraws the old meeting context using cached stages" do
    @meeting.update!(starts_at: @meeting.starts_at - 1.day)
    without_paid_providers { ExtractVotesJob.perform_now(@meeting.id) }
    assert_not @summary.reload.published?
    current = Meetings::MotionContext.capture(@meeting.id).manifest
    retained = @summary.generation_data.fetch("motion_context_manifest")
    assert_equal retained.fetch("context_sha256"), current.fetch("context_sha256")
    assert_not_equal retained.fetch("meeting_context"), current.fetch("meeting_context")
    assert_equal @original_publication.votes_extraction_id, @meeting.reload.minutes_publication.votes_extraction_id
    get meeting_path(@meeting)
    refute_includes response.body, OLD_CLAIM
  end

  test "explicit regeneration publishes current facts and an unchanged extraction rerun does not generate again" do
    refresh_votes
    assert_not @summary.reload.published?
    generate_summary
    assert_predicate @summary.reload, :published?
    assert_equal CURRENT_CLAIM, @summary.generation_data.fetch("headline")
    assert_includes @analysis_inputs.last, "yes=1"
    assert_equal @meeting.reload.minutes_publication_id, @summary.generation_data.dig("motion_context_manifest", "publication_id")
    get meeting_path(@meeting)
    assert_includes response.body, CURRENT_CLAIM
    refute_includes response.body, OLD_CLAIM
    get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
    assert_includes response.body, CURRENT_CLAIM
    refute_includes response.body, "motion_context_manifest"
    before = @summary.attributes
    without_paid_providers do
      assert_no_enqueued_jobs do
        ExtractVotesJob.perform_now(@meeting.id)
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end
    assert_equal before, @summary.reload.attributes
    assert_equal 2, @analysis_inputs.size
  end

  test "citation-only repair preserves the generated motion dependency receipt" do
    receipt = @summary.generation_data.fetch("motion_context_manifest")
    data = @summary.generation_data.except(*Citations::SummaryRepair::SERVER_FIELDS)
    run = PromptRun.create!(source: @meeting, prompt_template_key: "analyze_meeting_content", ai_model: "synthetic",
      response_body: data.to_json, placeholder_values: { "doc_text" => @document.extracted_text },
      messages: [ { "role" => "user", "content" => @document.extracted_text } ])
    without_paid_providers do
      result = Citations::SummaryRepair.new(summary_id: @summary.id, document_id: @document.id, prompt_run_id: run.id).call(apply: true)
      assert result[:applied]
    end
    assert_equal receipt, @summary.reload.generation_data.fetch("motion_context_manifest")
    assert_predicate @summary, :published?
  ensure
    run&.destroy!
  end

  test "fact publication waits for the first summary and withdraws it without a foreign key deadlock" do
    @summary.destroy!
    entered, release, started, errors = Queue.new, Queue.new, Queue.new, Queue.new
    workers = []
    meeting_id = @meeting.id
    callback = -> do
      if self.meeting_id == meeting_id
        entered << true
        release.pop
      end
    end
    MeetingSummary.set_callback(:create, :before, callback)
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { generate_summary(providers: false) }
      rescue => error
        errors << error
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          refresh_votes(providers: false)
        end
      rescue => error
        errors << error
      end
      pid = Timeout.timeout(10) { started.pop }
      wait_type = nil
      Timeout.timeout(10) do
        while workers.last.alive?
          wait_type = ActiveRecord::Base.uncached do
            ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
          end
          break if wait_type == "Lock"
          sleep 0.01
        end
      end
      assert_equal "Lock", wait_type, "Fact publication must wait for the first summary's captured context"
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert errors.empty?, "Unexpected worker error: #{errors.pop unless errors.empty?}"
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    summary = @meeting.meeting_summaries.sole
    assert_equal OLD_CLAIM, summary.generation_data.fetch("headline")
    assert_not summary.published?
    assert_enqueued_jobs 0, only: [ SummarizeMeetingJob, ExtractVotesJob ]
    get meeting_path(@meeting)
    refute_includes response.body, OLD_CLAIM
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    MeetingSummary.skip_callback(:create, :before, callback) if callback
  end

  private

  def generate_summary(providers: true, mode: :full)
    operation = ->(*) { SummarizeMeetingJob.perform_now(@meeting.id, mode: mode, enqueue_followups: false) }
    providers ? withdrawal_providers(&operation) : operation.call
  end

  def revise_template(kind)
    key = Minutes::Input::TASKS.fetch(kind)
    template = PromptTemplate.find_by(key: key)
    unless @templates.key?(key)
      @templates[key] = template && { attributes: template.attributes.except("id"), version_ids: template.versions.pluck(:id) }
    end
    template ||= PromptTemplate.new(key: key, name: "Synthetic fact extraction", model_tier: "default")
    template.update!(instructions: "Synthetic explicitly revised #{kind} extraction {{text}}")
  end

  def refresh_votes(providers: true)
    revise_template("votes")
    data = JSON.parse(@provider.extract_votes)
    data.fetch("motions").sole.fetch("votes").sole["value"] = "yes"
    @provider.define_singleton_method(:extract_votes) { |*, **| data.to_json }
    operation = ->(*) { ExtractVotesJob.perform_now(@meeting.id, refresh: true) }
    providers ? withdrawal_providers(&operation) : operation.call
  end
end
