require "test_helper"
require "timeout"
require_relative "../support/briefing_withdrawal_scenario"

class AgendaBriefingContextTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @extra_meetings = []
    @previous_setting = SiteSetting.first
    @previous_mode = @previous_setting&.access_mode
    SiteSetting.instance.update!(access_mode: "open")
    build_withdrawal_scenario
    @agenda_document = @meeting.meeting_documents.create!(document_type: "agenda_pdf",
      source_url: "https://example.test/preview-agenda.pdf", extracted_text: "#{@topic.name}. #{@other.name}.")
    _, secret = ApiAccessToken.issue!(user: @actor, name: "Synthetic agenda reader", expires_in: 1.day)
    @bearer = { "Authorization" => "Bearer #{secret}" }
    @contexts = []
    @catalogs = []
    @retrieval.define_singleton_method(:retrieve_context) { |*| [] }
    @retrieval.define_singleton_method(:format_context) { |*| "" }
    @provider.define_singleton_method(:prepare_kb_context) { |*| "Synthetic independent knowledge context" }
    contexts, catalogs = @contexts, @catalogs
    @provider.define_singleton_method(:analyze_meeting_content) do |_text, context, type, **options|
      raise "Unexpected summary mode" unless type == "agenda"
      contexts << context
      catalogs << options.fetch(:source_catalog)
      { headline: context.include?(CLAIM) ? CLAIM : "Synthetic supported agenda preview",
        highlights: [], public_input: [], item_details: [] }.to_json
    end
    clear_enqueued_jobs
  end

  teardown do
    ApiAccessToken.where(user_id: @actor&.id).delete_all
    summary_ids = MeetingSummary.where(meeting_id: [ @meeting&.id ] + @extra_meetings.map(&:id)).pluck(:id)
    KnowledgeSource.where(meeting_id: [ @meeting&.id ] + @extra_meetings.map(&:id)).destroy_all
    @extra_meetings.each(&:destroy!)
    clean_withdrawal_scenario
    AuditEvent.where(subject_type: "MeetingSummary", subject_id: summary_ids).delete_all
    if @previous_setting
      @previous_setting.update!(access_mode: @previous_mode)
    else
      SiteSetting.first&.destroy!
    end
  end

  test "identity correction withdraws an already published agenda preview without generating a replacement" do
    generate_preview
    summary = @meeting.meeting_summaries.sole
    original = summary.attributes
    assert_resident_headline CLAIM
    receipt = summary.generation_data.fetch("topic_context_manifest")
    assert_equal [ @topic.id, @other.id ], receipt.fetch("entries").map { |entry| entry.fetch("topic_id") }
    independent = extra_preview_meeting(@other.name)
    generate_preview(meeting: independent)
    independent_summary = independent.meeting_summaries.sole
    independent_before = independent_summary.attributes
    image = @meeting.generated_images.create!(status: "ready", purpose: "feature_and_og", source_summary: summary)
    clear_enqueued_jobs
    without_paid_providers do
      withdraw_decision
      get meeting_path(@meeting)
      assert_response :success
      refute_includes response.body, CLAIM
      assert_includes response.body, "supporting evidence changed"
      assert_select "a[href='#{@agenda_document.source_url}']"
      get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
      assert_nil response.parsed_body.dig("data", "summary")
    end
    assert_not summary.reload.published?
    assert_equal original.fetch("generation_data"), summary.generation_data
    assert_equal "superseded", image.reload.status
    assert_equal independent_before, independent_summary.reload.attributes
    audit = AuditEvent.where(subject: summary, action: "meeting_summary.topic_context_withdrawn").sole
    assert_equal "Automated", audit.actor_label
    assert_equal receipt, audit.metadata.fetch("topic_context_manifest")
    assert_equal [ @other.id ], audit.metadata.fetch("current_topic_context_manifest").fetch("entries").map { |entry| entry.fetch("topic_id") }
    assert_equal 2, @contexts.size
    assert_enqueued_jobs 0, only: SummarizeMeetingJob
    get meeting_path(independent)
    assert_includes response.body, "Synthetic supported agenda preview"
    refute_includes response.body, "Private synthetic identity correction"
  end

  test "an identity withdrawal is excluded from the next agenda input and resident preview while unrelated context survives" do
    generate_preview
    assert_equal 1, @contexts.size
    assert_equal 2, @contexts.last.scan("## Known topic:").size
    assert_includes @contexts.last, CLAIM
    assert_includes @contexts.last, STORY
    assert_includes @contexts.last, @other_briefing.headline
    assert_resident_headline CLAIM
    without_paid_providers { withdraw_decision }
    assert_not @meeting.meeting_summaries.sole.reload.published?

    generate_preview
    assert_equal 2, @contexts.size
    assert_equal 1, @contexts.last.scan("## Known topic:").size
    refute_includes @contexts.last, CLAIM
    refute_includes @contexts.last, STORY
    assert_includes @contexts.last, @other_briefing.headline
    assert_includes @contexts.last, "Synthetic independent knowledge context"
    assert_equal [ @agenda_document.id ], @catalogs.last.map { |source| source.fetch("document_id") }
    assert_equal 1, @meeting.meeting_summaries.count
    assert_resident_headline "Synthetic supported agenda preview", absent: CLAIM
    assert_predicate @meeting.meeting_summaries.sole, :published?
    assert_equal [ @other.id ], @meeting.meeting_summaries.sole.generation_data.fetch("topic_context_manifest")
      .fetch("entries").map { |entry| entry.fetch("topic_id") }
  end

  test "a source withdrawal during generation discards the response without followups and preserves an earlier independent preview" do
    earlier = @meeting.meeting_summaries.create!(summary_type: "agenda_preview", generation_data: {
      headline: "Synthetic earlier independent preview", highlights: [], public_input: [], item_details: []
    })
    original = earlier.attributes
    assert_resident_headline "Synthetic earlier independent preview"
    provider = @provider.method(:analyze_meeting_content)
    document = @document
    @provider.define_singleton_method(:analyze_meeting_content) do |*args, **kwargs|
      result = provider.call(*args, **kwargs)
      URI.stub(:open, ->(*) { StringIO.new("Synthetic corrected minutes bytes") }) { Documents::DownloadJob.perform_now(document.id) }
      result
    end

    GeneratedImages::Config.stub(:enabled?, true) do
      generate_preview
    end
    assert_equal 1, @contexts.size
    assert_includes @contexts.sole, CLAIM
    assert_nil @topic.reload.published_topic_briefing
    assert_equal original, earlier.reload.attributes
    assert_no_preview_followups
    assert_resident_headline "Synthetic earlier independent preview", absent: CLAIM
  end

  test "a changed published briefing during generation cannot create a first preview" do
    provider = @provider.method(:analyze_meeting_content)
    topic, briefing = @topic, @briefing
    @provider.define_singleton_method(:analyze_meeting_content) do |*args, **kwargs|
      result = provider.call(*args, **kwargs)
      topic.with_lock { briefing.update!(headline: "Synthetic corrected interpretation") }
      result
    end
    generate_preview
    assert_equal 1, @contexts.size
    assert_includes @contexts.sole, CLAIM
    assert_empty @meeting.meeting_summaries
    assert_no_preview_followups
    get meeting_path(@meeting)
    assert_response :success
    refute_includes response.body, CLAIM
    get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
    assert_response :success
    assert_nil response.parsed_body.dig("data", "summary")
  end

  test "changes outside the consumed context do not discard a supported preview" do
    provider = @provider.method(:analyze_meeting_content)
    topic, briefing = @topic, @briefing
    @provider.define_singleton_method(:analyze_meeting_content) do |*args, **kwargs|
      result = provider.call(*args, **kwargs)
      topic.with_lock { briefing.touch }
      result
    end
    generate_preview
    assert_equal 1, @contexts.size
    assert_resident_headline CLAIM
  end

  test "publication waits for an uncommitted identity withdrawal then rejects the old context" do
    ready, release, started = Queue.new, Queue.new, Queue.new
    workers = []
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          @topic.with_lock do
            withdraw_decision
            ready << true
            release.pop
          end
        end
      end
      Timeout.timeout(10) { ready.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
        end
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
      assert_equal "Lock", wait_type, "Publication must wait for the topic correction transaction"
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert_equal 1, @contexts.size
    assert_includes @contexts.sole, CLAIM
    assert_empty @meeting.meeting_summaries
    assert_nil @topic.reload.published_topic_briefing
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
  end

  test "a changed historical source withdraws a future preview through its consumed briefing" do
    future = extra_preview_meeting(@topic.name)
    generate_preview(meeting: future)
    summary = future.meeting_summaries.sole
    original = summary.attributes
    agenda_source = summary.generation_data.fetch("source_catalog")
    assert_equal [ future.meeting_documents.sole.id ], agenda_source.map { |source| source.fetch("document_id") }
    assert_empty summary.generation_data.dig("motion_context_manifest", "source_catalog")
    get meeting_path(future)
    assert_includes response.body, CLAIM
    etag = response.headers.fetch("ETag")
    since = Time.current
    travel 2.seconds do
      without_paid_providers do
        URI.stub(:open, ->(*) { StringIO.new("Synthetic corrected historical source") }) { Documents::DownloadJob.perform_now(@document.id) }
        get meeting_path(future), headers: { "If-None-Match" => etag }
        assert_response :success
        refute_includes response.body, CLAIM
        assert_select "a[href='#{future.meeting_documents.sole.source_url}']"
        get "/api/v1/meetings", params: { q: CLAIM }, headers: @bearer
        assert_empty response.parsed_body.fetch("data")
        get "/api/v1/meetings", params: { updated_since: since.iso8601(6) }, headers: @bearer
        assert_includes response.parsed_body.fetch("data").map { |row| row.fetch("id") }, future.id
      end
    end
    assert_not summary.reload.published?
    assert_equal original.fetch("generation_data"), summary.generation_data
    assert_equal 2, @document.reload.source_versions.count
    assert Topics::GenerationEvidence.sources_current?(agenda_source)
  end

  test "metadata and unconsumed prose preserve the preview until its consumed coming-up text changes" do
    @briefing.update!(editorial_content: "Synthetic long context " * 80 + " Original ending")
    generate_preview
    summary = @meeting.meeting_summaries.sole
    original = summary.attributes
    clear_enqueued_jobs
    without_paid_providers do
      @briefing.touch
      @briefing.update!(record_content: "Synthetic unconsumed record",
        editorial_content: "Synthetic long context " * 80 + " Changed ending")
      @topic.update!(description: "Synthetic unconsumed description")
      assert_equal original, summary.reload.attributes
      assert_no_enqueued_jobs
      @briefing.update!(upcoming_headline: "Synthetic changed next step")
    end
    assert_not summary.reload.published?
    assert_equal 1, @contexts.size
    get meeting_path(@meeting)
    refute_includes response.body, CLAIM
  end

  test "failed preview audit rolls back the briefing change and a deterministic retry withdraws it" do
    generate_preview
    summary = @meeting.meeting_summaries.sole
    previous_summary, previous_briefing = summary.attributes, @briefing.attributes
    record = AuditEvent.method(:record!)
    without_paid_providers do
      AuditEvent.stub(:record!, ->(**args) {
        raise "Synthetic preview audit failure" if args[:action] == "meeting_summary.topic_context_withdrawn"
        record.call(**args)
      }) do
        assert_raises(RuntimeError) { @briefing.update!(headline: "Synthetic corrected context") }
      end
      assert_equal previous_briefing, @briefing.reload.attributes
      assert_equal previous_summary, summary.reload.attributes
      assert_resident_headline CLAIM
      @briefing.update!(headline: "Synthetic corrected context")
    end
    assert_not summary.reload.published?
    assert_equal 1, AuditEvent.where(subject: summary, action: "meeting_summary.topic_context_withdrawn").count
  end

  { name: "Synthetic revised cedar improvements", status: "blocked", resident_impact_score: 2 }.each do |attribute, value|
    test "a consumed topic #{attribute} change withdraws its preview" do
      generate_preview
      assert_resident_headline CLAIM
      without_paid_providers { @topic.update!(attribute => value) }
      assert_not @meeting.meeting_summaries.sole.reload.published?
      get meeting_path(@meeting)
      refute_includes response.body, CLAIM
    end
  end

  test "removing the alias that established relevance withdraws the captured context" do
    original_name = @topic.name
    @topic.update!(name: "Synthetic unrelated concern")
    topic_alias = @topic.topic_aliases.create!(name: original_name)
    generate_preview
    assert_resident_headline CLAIM
    without_paid_providers { topic_alias.destroy! }
    assert_not @meeting.meeting_summaries.sole.reload.published?
    get meeting_path(@meeting)
    refute_includes response.body, CLAIM
  end

  test "admin alias move withdraws the preview that depended on its original ownership" do
    original_name = @topic.name
    @topic.update!(name: "Synthetic unrelated concern")
    topic_alias = @topic.topic_aliases.create!(name: original_name)
    generate_preview
    assert_resident_headline CLAIM
    summary = @meeting.meeting_summaries.sole
    original = summary.generation_data
    image = @meeting.generated_images.create!(status: "ready", purpose: "feature_and_og", source_summary: summary)
    independent = extra_preview_meeting(@other.name)
    generate_preview(meeting: independent)
    independent_before = independent.meeting_summaries.sole.attributes
    session = sign_in_as_admin(@actor)
    clear_enqueued_jobs

    without_paid_providers do
      post move_alias_admin_topic_path(@topic), params: {
        alias_id: topic_alias.id, target_topic_id: @other.id, reason: "Synthetic ownership correction", q: "synthetic"
      }
      assert_redirected_to admin_topic_url(@topic, q: "synthetic")
      assert_equal @other.id, topic_alias.reload.topic_id
      assert_equal @other.id, Topic.find_by_name_or_alias(original_name).id
      assert_equal "Synthetic ownership correction", TopicReviewEvent.where(topic: @other, action: "alias_moved").sole.reason
      assert_not summary.reload.published?
      assert_equal original, summary.generation_data
      assert_equal "superseded", image.reload.status
      assert_equal independent_before, independent.meeting_summaries.sole.reload.attributes
      assert_equal 1, AuditEvent.where(subject: summary, action: "meeting_summary.topic_context_withdrawn").count
      cookies.delete(:session_id)
      get meeting_path(@meeting)
      assert_response :success
      refute_includes response.body, CLAIM
      assert_select "a[href='#{@agenda_document.source_url}']"
      get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
      assert_response :success
      assert_nil response.parsed_body.dig("data", "summary")
      assert_enqueued_jobs 0
    end
  ensure
    session&.destroy!
    @actor.passkey_credentials.delete_all
  end

  test "topic merge withdraws the consumed retired identity without replacing its receipt" do
    generate_preview
    summary = @meeting.meeting_summaries.sole
    original = summary.generation_data
    independent = extra_preview_meeting(@other.name)
    generate_preview(meeting: independent)
    before = independent.meeting_summaries.sole.attributes
    without_paid_providers { Topics::MergeService.new(source_topic: @topic, target_topic: @other).call }
    assert_not summary.reload.published?
    assert_equal original, summary.generation_data
    assert_equal before, independent.meeting_summaries.sole.attributes
    assert_equal @other.id, Topic.find_by_name_or_alias(@topic.name).id
    get meeting_path(@meeting)
    refute_includes response.body, CLAIM
  end

  test "briefing removal withdraws a saved preview while its original context remains retained" do
    generate_preview
    summary = @meeting.meeting_summaries.sole
    original = summary.generation_data
    without_paid_providers { @briefing.destroy! }
    assert_not summary.reload.published?
    assert_equal original, summary.generation_data
    get meeting_path(@meeting)
    refute_includes response.body, CLAIM
    assert_select "a[href='#{@agenda_document.source_url}']"
  end

  test "citation-only repair preserves the server-owned topic context receipt" do
    generate_preview
    summary = @meeting.meeting_summaries.sole
    receipt = summary.generation_data.fetch("topic_context_manifest")
    data = { headline: CLAIM, highlights: [], public_input: [], item_details: [] }
    run = PromptRun.create!(source: @meeting, prompt_template_key: "analyze_meeting_content", ai_model: "synthetic",
      response_body: data.to_json, placeholder_values: { "doc_text" => @agenda_document.extracted_text },
      messages: [ { "role" => "user", "content" => @agenda_document.extracted_text } ])
    without_paid_providers do
      result = Citations::SummaryRepair.new(summary_id: summary.id, document_id: @agenda_document.id, prompt_run_id: run.id).call(apply: true)
      assert result[:applied]
    end
    assert_equal receipt, summary.reload.generation_data.fetch("topic_context_manifest")
    assert_predicate summary, :published?
  ensure
    run&.destroy!
  end

  test "knowledge generated from changed topic context is discarded and withdrawn queued work makes no calls" do
    generate_preview
    response_json = { entries: [ { title: "Synthetic agenda knowledge", body: "Synthetic context", confidence: 0.9, reasoning: "Synthetic basis" } ] }.to_json
    @provider.define_singleton_method(:extract_knowledge) { |**| response_json }
    withdrawal_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    assert_equal 1, @meeting.knowledge_sources.count
    briefing = @briefing
    @provider.define_singleton_method(:extract_knowledge) do |**|
      briefing.update!(headline: "Synthetic changed context during knowledge generation")
      response_json
    end
    withdrawal_providers { ExtractKnowledgeJob.perform_now(@meeting.id) }
    assert_equal 1, @meeting.knowledge_sources.count
    clear_enqueued_jobs
    without_paid_providers do
      ExtractKnowledgeJob.perform_now(@meeting.id)
      PruneHollowAppearancesJob.perform_now(@meeting.id)
    end
    assert_no_enqueued_jobs
  end

  test "a direct briefing update waits for first preview publication then withdraws that preview" do
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
        ActiveRecord::Base.connection_pool.with_connection { generate_preview(providers: false) }
      rescue => error
        errors << error
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          @briefing.update!(headline: "Synthetic concurrent corrected briefing")
        end
      rescue => error
        errors << error
      end
      assert_worker_wait(started, workers.last)
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert errors.empty?, "Unexpected worker error: #{errors.pop unless errors.empty?}"
    summary = @meeting.meeting_summaries.sole
    assert_equal CLAIM, summary.generation_data.fetch("headline")
    assert_not summary.published?
    get meeting_path(@meeting)
    refute_includes response.body, CLAIM
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    MeetingSummary.skip_callback(:create, :before, callback) if callback
  end

  test "knowledge publication waits for topic context before locking the summary and avoids a deadlock" do
    generate_preview
    entered, release, started, errors = Queue.new, Queue.new, Queue.new, Queue.new
    workers = []
    briefing_id = @briefing.id
    callback = -> do
      if id == briefing_id
        entered << true
        release.pop
      end
    end
    TopicBriefing.set_callback(:update, :after, callback)
    topic_name = @topic.name
    @provider.define_singleton_method(:extract_knowledge) do |**|
      { entries: [ { title: "Synthetic concurrent agenda knowledge", body: "Synthetic context", confidence: 0.9,
        reasoning: "Synthetic support", topic_names: [ topic_name ] } ] }.to_json
    end
    clear_enqueued_jobs
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { @briefing.update!(headline: "Synthetic pending correction") }
      rescue => error
        errors << error
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          ExtractKnowledgeJob.perform_now(@meeting.id)
        end
      rescue => error
        errors << error
      end
      assert_worker_wait(started, workers.last)
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert errors.empty?, "Unexpected worker error: #{errors.pop unless errors.empty?}"
    assert_empty @meeting.knowledge_sources
    assert_not @meeting.meeting_summaries.sole.reload.published?
    assert_enqueued_jobs 0, only: ExtractKnowledgeJob
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    TopicBriefing.skip_callback(:update, :after, callback) if callback
  end

  test "knowledge linking an additional topic cannot deadlock with a multi-topic context writer" do
    @agenda_document.update!(extracted_text: @other.name)
    generate_preview
    assert_equal [ @other.id ], @meeting.meeting_summaries.sole.generation_data.dig("topic_context_manifest", "entries").map { |entry| entry.fetch("topic_id") }
    entered, release, started, errors = Queue.new, Queue.new, Queue.new, Queue.new
    workers = []
    meeting_id = @meeting.id
    callback = -> do
      if self.meeting_id == meeting_id
        entered << true
        release.pop
      end
    end
    KnowledgeSource.set_callback(:create, :before, callback)
    topic_name = @topic.name
    @provider.define_singleton_method(:extract_knowledge) do |**|
      { entries: [ { title: "Synthetic additional topic knowledge", body: "Synthetic context", confidence: 0.9,
        reasoning: "Synthetic support", topic_names: [ topic_name ] } ] }.to_json
    end
    clear_enqueued_jobs
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { ExtractKnowledgeJob.perform_now(@meeting.id) }
      rescue => error
        errors << error
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          @topic.with_lock { @other_briefing.update!(headline: "Synthetic concurrent multiple-topic update") }
        end
      rescue => error
        errors << error
      end
      assert_worker_wait(started, workers.last)
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert errors.empty?, "Unexpected worker error: #{errors.pop unless errors.empty?}"
    assert_equal 1, @meeting.knowledge_sources.count
    assert_equal [ @topic.id ], @meeting.knowledge_sources.sole.topics.pluck(:id)
    assert_not @meeting.meeting_summaries.sole.reload.published?
    assert_enqueued_jobs 0, only: ExtractKnowledgeJob
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    KnowledgeSource.skip_callback(:create, :before, callback) if callback
  end

  {
    "an alias reassignment while knowledge waits rejects its captured topic mapping" => 0.9,
    "a rejected knowledge alias change does not block an accepted independent entry" => 0.1
  }.each do |name, confidence|
    test name do
      @agenda_document.update!(extracted_text: @other.name)
      topic_alias = @topic.topic_aliases.create!(name: "Synthetic separate knowledge subject")
      generate_preview
      entered, release, started, errors = Queue.new, Queue.new, Queue.new, Queue.new
      workers = []
      alias_id, alias_name = topic_alias.id, topic_alias.name
      callback = -> do
        if id == alias_id
          entered << true
          release.pop
        end
      end
      TopicAlias.set_callback(:update, :after, callback)
      independent_name = @other.name
      @provider.define_singleton_method(:extract_knowledge) do |**|
        entries = [ { title: "Synthetic reassigned knowledge", body: "Synthetic context", confidence: confidence,
          reasoning: "Synthetic support", topic_names: [ alias_name ] } ]
        if confidence == 0.1
          entries << { title: "Synthetic independent knowledge", body: "Synthetic accepted context", confidence: 0.9,
            reasoning: "Synthetic support", topic_names: [ independent_name ] }
        end
        { entries: entries }.to_json
      end
      clear_enqueued_jobs
      withdrawal_providers do
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { topic_alias.update!(topic: @other) }
        rescue => error
          errors << error
        end
        Timeout.timeout(10) { entered.pop }
        workers << Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do |connection|
            started << connection.select_value("SELECT pg_backend_pid()")
            ExtractKnowledgeJob.perform_now(@meeting.id)
          end
        rescue => error
          errors << error
        end
        assert_worker_wait(started, workers.last)
        release << true
        Timeout.timeout(10) { workers.each(&:value) }
      end
      assert errors.empty?, "Unexpected worker error: #{errors.pop unless errors.empty?}"
      if confidence == 0.9
        assert_empty @meeting.knowledge_sources
        assert_no_enqueued_jobs
      else
        assert_equal 1, @meeting.knowledge_sources.count
        assert_equal "Synthetic independent knowledge", @meeting.knowledge_sources.sole.title
        assert_equal [ @other.id ], @meeting.knowledge_sources.sole.topics.pluck(:id)
        assert_enqueued_jobs 1, only: AutoTriageKnowledgeJob
        assert_enqueued_jobs 0, only: ExtractKnowledgeJob
      end
      assert_equal @other.id, Topic.find_by_name_or_alias(alias_name).id
      assert_predicate @meeting.meeting_summaries.sole.reload, :published?
    ensure
      release << true if release
      workers&.each { |worker| worker.join(10) }
      TopicAlias.skip_callback(:update, :after, callback) if callback
    end
  end

  private

  def assert_no_preview_followups
    assert_enqueued_jobs 0, only: [ GeneratedImages::GenerateForMeetingJob, Topics::GenerateTopicBriefingJob ]
  end

  def generate_preview(meeting: @meeting, providers: true)
    operation = ->(*) { SummarizeMeetingJob.perform_now(meeting.id, mode: :agenda_preview) }
    providers ? withdrawal_providers(&operation) : operation.call
  end

  def extra_preview_meeting(agenda_text)
    meeting = Meeting.create!(body_name: "Synthetic future council", starts_at: 2.days.from_now,
      detail_page_url: "https://example.test/future-preview-#{@extra_meetings.size}")
    @extra_meetings << meeting
    meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: agenda_text,
      source_url: "https://example.test/future-agenda-#{meeting.id}.pdf")
    meeting
  end

  def assert_worker_wait(started, worker)
    pid = Timeout.timeout(10) { started.pop }
    wait_type = nil
    Timeout.timeout(10) do
      while worker.alive?
        wait_type = ActiveRecord::Base.uncached do
          ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
        end
        break if wait_type == "Lock"
        sleep 0.01
      end
    end
    assert_equal "Lock", wait_type, "Publication must serialize with the captured topic context"
  end

  def assert_resident_headline(headline, absent: nil)
    assert_equal 1, @meeting.meeting_summaries.count, "The supported preview must be persisted"
    assert_equal headline, @meeting.meeting_summaries.sole.generation_data.fetch("headline")
    get meeting_path(@meeting)
    assert_response :success
    assert_includes response.body, headline
    refute_includes response.body, absent if absent
    get "/api/v1/meetings/#{@meeting.id}", headers: @bearer
    assert_response :success
    assert_includes response.body, headline
    refute_includes response.body, "topic_context_manifest"
    refute_includes response.body, absent if absent
  end
end
