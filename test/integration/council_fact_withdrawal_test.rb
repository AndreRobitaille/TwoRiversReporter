require "test_helper"
require "timeout"
require_relative "../support/briefing_withdrawal_scenario"

class CouncilFactWithdrawalTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @previous_setting = SiteSetting.first
    @previous_mode = @previous_setting&.access_mode
    SiteSetting.instance.update!(access_mode: "open")
    # The first synthetic provider misreads the unchanged passage's yes vote.
    # A later explicit extraction corrects it; neither output is human approval.
    @templates = {}
    build_withdrawal_scenario(vote_value: "no")
    @original_publication = @meeting.reload.minutes_publication
    @original_briefing = @briefing.attributes
    @original_source = Citations::SourceCatalog.snapshot(@document.reload)
    _, secret = ApiAccessToken.issue!(user: @actor, name: "Synthetic fact reader", expires_in: 1.day)
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
    ApiAccessToken.where(user_id: @actor&.id).delete_all
    Session.where(user_id: @actor&.id).delete_all
    PasskeyCredential.where(user_id: @actor&.id).delete_all
    KnownContext.where(user_id: @actor&.id).delete_all
    clean_withdrawal_scenario
    if @previous_setting
      @previous_setting.update!(access_mode: @previous_mode)
    else
      SiteSetting.first&.destroy!
    end
  end

  test "corrected facts from the same document withdraw dependent prose and images before continuity runs" do
    other = @other_briefing.attributes
    observation = @event.decision_observation
    decision_id = observation.identity_assignment.council_decision_id
    image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", source_briefing: @briefing)
    image.file.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "synthetic.png", content_type: "image/png")
    get topic_path(@topic)
    assert_includes response.body, STORY
    assert_select ".topic-feature-image img", count: 1
    etag = response.headers.fetch("ETag")
    assert_member_vote "No"
    since = Time.current

    travel 2.seconds do
      refresh_votes
      assert_nil @topic.reload.published_topic_briefing
      assert_nil @briefing.reload.withdrawal_correction_id
      assert_equal @original_source, Citations::SourceCatalog.snapshot(@document.reload)
      assert_equal 1, @document.source_versions.count
      assert_equal 1, @document.source_versions.sole.text_versions.count
      assert_equal 2, @meeting.minutes_publications.count
      assert_equal 2, @meeting.minutes_extractions.where(kind: "votes").count
      assert_equal 1, @meeting.minutes_extractions.where(kind: "attendance").count
      assert_equal "no", observation.reload.data.fetch("votes").sole.fetch("value")
      assert_equal "yes", @meeting.motions.sole.votes.sole.value
      assert_equal decision_id, @meeting.motions.sole.decision_observation.identity_assignment.council_decision_id
      assert_equal @original_briefing.slice("generation_data", "editorial_content", "last_full_generation_at"),
        @briefing.attributes.slice("generation_data", "editorial_content", "last_full_generation_at")
      assert_equal other, @other_briefing.reload.attributes
      assert_equal "superseded", image.reload.status
      assert image.file.attached?

      without_paid_providers do
        get topic_path(@topic), headers: { "If-None-Match" => etag }
        assert_response :success
        refute_includes response.body, STORY
        assert_select ".topic-feature-image img", count: 0
        assert_select "a[href='#{meeting_path(@meeting)}']"
        assert_member_vote "Yes"
        get "/api/v1/topics/#{@topic.id}", headers: @bearer
        assert_nil response.parsed_body.dig("data", "briefing")
        get "/api/v1/topics", params: { updated_since: since.iso8601(6) }, headers: @bearer
        assert_equal [ @topic.id ], response.parsed_body.fetch("data").map { |row| row.fetch("id") }
      end
    end
    audit = AuditEvent.where(subject: @briefing, action: "topic_briefing.facts_withdrawn").sole
    assert_nil audit.actor_id
    assert_equal "Automated", audit.actor_label
    assert_equal "motion_evidence_changed", audit.metadata.fetch("reason")
    assert_equal "fact_publication_dependencies_v1", audit.metadata.fetch("method")
    assert_equal @original_publication.id, audit.metadata.dig("previous_publication", "id")
    assert_equal @meeting.reload.minutes_publication_id, audit.metadata.dig("current_publication", "id")
    assert_equal @original_briefing.fetch("generation_data").fetch("evidence_manifest"), audit.metadata.fetch("evidence_manifest")
    assert_enqueued_jobs 1, only: Topics::UpdateContinuityJob
    assert_enqueued_jobs 0, only: [ Topics::GenerateTopicBriefingJob, GeneratedImages::GenerateForTopicJob ]
    sign_in_as(@actor)
    get admin_audit_events_path
    assert_response :success
    assert_select "tbody tr", text: /Automated.*topic_briefing\.facts_withdrawn.*Topic: #{Regexp.escape(@topic.name)}/m, count: 1
  end

  test "unchanged publication and compatible attendance refresh preserve the motion-backed briefing" do
    without_paid_providers do
      assert_no_enqueued_jobs do
        ExtractVotesJob.perform_now(@meeting.id)
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end
    assert_equal @original_briefing, @briefing.reload.attributes
    revise_template("attendance")
    withdrawal_providers { ExtractCommitteeMembersJob.perform_now(@meeting.id, refresh: true) }
    assert_not_equal @original_publication.id, @meeting.reload.minutes_publication_id
    assert_equal @original_publication.votes_extraction_id, @meeting.minutes_publication.votes_extraction_id
    assert_equal @original_briefing, @briefing.reload.attributes
    assert_empty AuditEvent.where(subject: @briefing)
    assert_member_vote "No"
  end

  test "a failed withdrawal audit rolls back the fact projection and retries completed stages without AI" do
    original_motion_ids = @meeting.motions.pluck(:id)
    original_attendance_ids = @meeting.meeting_attendances.pluck(:id)
    AuditEvent.stub(:record!, ->(**) { raise "Synthetic audit persistence failure" }) do
      assert_raises(RuntimeError) { refresh_votes }
    end
    assert_equal @original_publication.id, @meeting.reload.minutes_publication_id
    assert_equal original_motion_ids, @meeting.motions.pluck(:id)
    assert_equal original_attendance_ids, @meeting.meeting_attendances.pluck(:id)
    assert_equal @original_briefing, @briefing.reload.attributes
    assert_equal 2, @meeting.minutes_extractions.where(kind: "votes", status: "completed").count
    assert_equal 1, @meeting.minutes_publications.count
    assert_enqueued_jobs 0, only: Topics::UpdateContinuityJob
    assert_member_vote "No"

    without_paid_providers { ExtractVotesJob.perform_now(@meeting.id) }
    assert_nil @topic.reload.published_topic_briefing
    assert_member_vote "Yes"
    assert_equal 2, @meeting.minutes_publications.count
    assert_equal 1, AuditEvent.where(subject: @briefing, action: "topic_briefing.facts_withdrawn").count
    without_paid_providers { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal 1, AuditEvent.where(subject: @briefing, action: "topic_briefing.facts_withdrawn").count
  end

  test "date reprojection withdraws old dated motion context without another provider call" do
    get topic_path(@topic)
    assert_includes response.body, STORY
    @meeting.update!(starts_at: @meeting.starts_at - 1.day)
    without_paid_providers { ExtractVotesJob.perform_now(@meeting.id) }
    assert_nil @topic.reload.published_topic_briefing
    publication = @meeting.reload.minutes_publication
    assert_equal @original_publication.votes_extraction_id, publication.votes_extraction_id
    assert_equal @original_publication.attendance_extraction_id, publication.attendance_extraction_id
    assert_not_equal @original_publication.projection_context, publication.projection_context
    assert_equal 2, @meeting.minutes_extractions.count
    get topic_path(@topic)
    refute_includes response.body, STORY
    assert_member_vote "No"
  end

  test "a live legacy motion reference is withdrawn when its projection is replaced" do
    legacy_attributes = @event.attributes.slice("evidence_type", "lifecycle_status", "occurred_at", "source_ref")
    @event.destroy!
    legacy = @topic.topic_status_events.create!(legacy_attributes)
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id) }
    receipt = @briefing.reload.generation_data.fetch("evidence_manifest").fetch("motion_evidence").sole
    assert_equal legacy.id, receipt.fetch("event_id")
    assert_nil receipt.fetch("reference")
    assert_not_nil @topic.reload.published_topic_briefing
    get topic_path(@topic)
    assert_includes response.body, STORY

    refresh_votes
    assert_nil @topic.reload.published_topic_briefing
    assert_equal receipt, @briefing.reload.generation_data.fetch("evidence_manifest").fetch("motion_evidence").sole
    get topic_path(@topic)
    refute_includes response.body, STORY
    assert_member_vote "Yes"
  end

  test "a fact change during generation keeps the old completion withdrawn instead of publishing late output" do
    get topic_path(@topic)
    assert_response :success
    assert_includes response.body, STORY
    analyze = @provider.method(:analyze_topic_briefing)
    change = -> { refresh_votes(providers: false) }
    @provider.define_singleton_method(:analyze_topic_briefing) do |*args, **kwargs|
      response = analyze.call(*args, **kwargs)
      change.call
      JSON.parse(response).merge("headline" => "Synthetic late stale result").to_json
    end
    # A new alias changes the generation query without invalidating old facts.
    @topic.topic_aliases.create!(name: "Synthetic cedar project")
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id) }
    assert_nil @topic.reload.published_topic_briefing
    assert_equal @original_briefing.fetch("generation_data"), @briefing.reload.generation_data
    assert_equal @original_briefing.fetch("last_full_generation_at"), @briefing.last_full_generation_at
    get topic_path(@topic)
    refute_includes response.body, "Synthetic late stale result"
    refute_includes response.body, STORY
    assert_member_vote "Yes"
  end

  test "fact publication waits for a first briefing and withdraws its receipt without a meeting foreign key deadlock" do
    @briefing.destroy!
    entered, release, started, failures = Queue.new, Queue.new, Queue.new, Queue.new
    workers = []
    topic_id = @topic.id
    callback = -> do
      if self.topic_id == topic_id
        entered << true
        release.pop
      end
    end
    TopicBriefing.set_callback(:create, :before, callback)
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Topics::GenerateTopicBriefingJob.perform_now(topic_id: topic_id, meeting_id: @meeting.id)
        end
      rescue StandardError => error
        failures << error.class.name
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          refresh_votes(providers: false)
        end
      rescue StandardError => error
        failures << error.class.name
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
      assert_equal "Lock", wait_type, "Fact publication must serialize with the first briefing"
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
    assert failures.empty?, "Both transactions must commit; failures: #{failures.size.times.map { failures.pop }}"
    assert_enqueued_jobs 0, only: [ ExtractVotesJob, Topics::GenerateTopicBriefingJob ]
    assert_nil @topic.reload.published_topic_briefing
    @briefing = @topic.topic_briefing
    assert_not_nil @briefing
    assert_equal CLAIM, @briefing.headline
    assert_equal 1, AuditEvent.where(subject: @briefing, action: "topic_briefing.facts_withdrawn").count
    assert_member_vote "Yes"
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    TopicBriefing.skip_callback(:create, :before, callback) if callback
  end

  private

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

  def assert_member_vote(value)
    member = Member.find_by!(name: "Alex Example")
    get member_path(member)
    assert_response :success
    assert_select ".member-vote-row", count: 1
    assert_select ".vote-value", text: value, count: 1
  end
end
