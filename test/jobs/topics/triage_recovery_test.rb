require "test_helper"

class Topics::TriageRecoveryTest < ActiveJob::TestCase
  setup do
    seed_prompt_templates
    @topics = [ "harbor repair", "crosswalk lights", "water meter replacement" ].map { |name| Topic.create!(name: name, status: "proposed") }
    @service = Ai::OpenAiService.new
    @cache = ActiveSupport::Cache::MemoryStore.new
    @retrieval = Object.new
    def @retrieval.retrieve_context(*) = []
    def @retrieval.format_context(*) = ""
  end

  test "malformed provider plan is rejected whole then all valid decisions persist" do
    approvals = @topics.map { |t| { topic: t.name, approve: true, confidence: 0.99, rationale: "Substantive infrastructure work" } }
    malformed = %({"merge_map":[],"approvals":#{approvals.to_json},"blocks":[],"approvals":[]})
    valid = { merge_map: [], approvals: approvals, blocks: [] }.to_json
    calls = 0
    with_provider(lambda do |parameters:|
      calls += 1
      assert_equal "json_schema", parameters.dig(:response_format, :type)
      assert_equal true, parameters.dig(:response_format, :json_schema, :strict)
      assert_equal %w[approvals blocks merge_map], parameters.dig(:response_format, :json_schema, :schema, :required).sort
      assert_equal 3, Topic.where(id: @topics, status: "proposed").count
      completion(calls == 1 ? malformed : valid)
    end) do
      assert_enqueued_jobs 3, only: Topics::GenerateDescriptionJob do
        Topics::AutoTriageJob.perform_now
      end
    end
    assert_equal 2, calls
    assert_equal @topics.map(&:id).sort, Topic.approved.order(:id).pluck(:id)
    assert_equal 3, TopicReviewEvent.where(topic: @topics, action: "approved").count
    assert_equal [ malformed, valid ], PromptRun.for_template("triage_topics").order(:id).pluck(:response_body)
  end

  test "persistent malformed output stops after two calls without applying any decisions" do
    calls = 0
    with_provider(->(**) { calls += 1; completion('{"merge_map":[],"approvals":[],"blocks":"invalid"}') }) do
      assert_no_enqueued_jobs do
        assert_raises(Topics::TriageResponse::Invalid) { Topics::AutoTriageJob.perform_now }
      end
    end
    assert_equal 2, calls
    assert_equal 3, Topic.proposed.where(id: @topics).count
    assert_empty TopicReviewEvent.where(topic: @topics)
  end

  test "identical completed triage is skipped but changed context and expired cache run again" do
    calls = 0
    with_provider(->(**) { calls += 1; completion('{"merge_map":[],"approvals":[],"blocks":[]}') }) do
      2.times { Topics::AutoTriageJob.perform_now }
      assert_equal 1, calls
      Topic.create!(name: "new sewer project", status: "proposed")
      Topics::AutoTriageJob.perform_now
      assert_equal 2, calls
      travel 61.minutes do
        Topics::AutoTriageJob.perform_now
        assert_equal 3, calls
      end
    end
  end

  test "invalid response is not cached as completed" do
    calls = 0
    with_provider(->(**) { calls += 1; completion(calls <= 2 ? "invalid" : '{"merge_map":[],"approvals":[],"blocks":[]}') }) do
      assert_raises(JSON::ParserError) { Topics::AutoTriageJob.perform_now }
      Topics::AutoTriageJob.perform_now
      assert_equal 3, calls
    end
  end

  test "solid queue serializes global triage and releases the waiting run" do
    first = SolidQueue::Job.enqueue(Topics::AutoTriageJob.new)
    second = SolidQueue::Job.enqueue(Topics::AutoTriageJob.new)
    assert first.ready?
    assert second.blocked?
    assert_not second.ready?
    process = SolidQueue::Process.register(kind: "Worker", pid: Process.pid, hostname: "test", name: SecureRandom.uuid)
    claimed = SolidQueue::ReadyExecution.claim([ "default" ], 1, process.id).sole
    assert_equal first.id, claimed.job_id
    with_provider(->(**) { completion('{"merge_map":[],"approvals":[],"blocks":[]}') }) { claimed.perform }
    assert first.reload.finished?
    assert second.reload.ready?
    assert_not second.blocked?
  end

  private

  def completion(content)
    { "choices" => [ { "message" => { "content" => content } } ] }
  end

  def with_provider(provider, &block)
    Rails.stub :cache, @cache do
      RetrievalService.stub :new, @retrieval do
        @service.instance_variable_get(:@client).stub :chat, provider do
          Ai::OpenAiService.stub :new, @service, &block
        end
      end
    end
  end
end
