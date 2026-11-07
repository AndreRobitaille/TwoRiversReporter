require "test_helper"
require "timeout"
require_relative "../support/briefing_withdrawal_scenario"

class AgendaBriefingContextTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
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
    clean_withdrawal_scenario
    if @previous_setting
      @previous_setting.update!(access_mode: @previous_mode)
    else
      SiteSetting.first&.destroy!
    end
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

  private

  def assert_no_preview_followups
    assert_enqueued_jobs 0, only: [ GeneratedImages::GenerateForMeetingJob, Topics::GenerateTopicBriefingJob ]
  end

  def generate_preview
    withdrawal_providers { SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview) }
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
    refute_includes response.body, absent if absent
  end
end
