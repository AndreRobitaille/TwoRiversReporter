require "test_helper"
require "minitest/mock"

class SummarizeMeetingJobTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
    @topic = Topic.create!(name: "Budget", status: "approved")

    @item = @meeting.agenda_items.create!(
      title: "Budget Review",
      order_index: 1
    )
    @item.topics << @topic
  end

  test "generates meeting summary with generation_data from minutes" do
    doc = @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: The council approved the budget 5-2."
    )

    generation_data = {
      "headline" => "Council approved the budget",
      "highlights" => [
        { "text" => "Budget approved", "citation" => "Page 1", "vote" => "5-2", "impact" => "high" }
      ],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    # Meeting-level: prepare_kb_context + analyze_meeting_content called directly
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type|
      type == "minutes"
    end
    # Topic-level: still uses two-pass
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
    assert summary, "Should create a minutes_recap summary"
    assert_equal "minutes", summary.generation_data["source_type"]
    assert_equal generation_data["headline"], summary.generation_data["headline"]
    assert_nil summary.content
  end

  test "generates topic summary for approved topics" do
    # Mock OpenAI
    mock_ai = Minitest::Mock.new

    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end

    # Analyze call expectation
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end

    # Render call expectation
    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    # Stub RetrievalService
    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    # Verify DB state
    assert_equal 1, @meeting.topic_summaries.count
    summary = @meeting.topic_summaries.first
    assert_equal @topic, summary.topic
    assert_equal "## Topic Summary", summary.content
    assert_equal({ "factual_record" => [] }, summary.generation_data)

    # Verify mocks
    mock_ai.verify
  end

  test "AI resident impact score propagates to topic" do
    assert_nil @topic.resident_impact_score

    mock_ai = Minitest::Mock.new

    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end

    ai_response = {
      headline: "Test headline",
      factual_record: [],
      resident_impact: { score: 4, rationale: "Affects property taxes" }
    }.to_json

    mock_ai.expect :analyze_topic_summary, ai_response do |arg|
      arg.is_a?(Hash)
    end

    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    @topic.reload
    assert_equal 4, @topic.resident_impact_score

    mock_ai.verify
  end

  test "admin-locked resident impact score is not overwritten by AI" do
    @topic.update!(resident_impact_score: 5, resident_impact_overridden_at: 10.days.ago)

    mock_ai = Minitest::Mock.new

    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end

    ai_response = {
      headline: "Test headline",
      factual_record: [],
      resident_impact: { score: 2, rationale: "Minor effect" }
    }.to_json

    mock_ai.expect :analyze_topic_summary, ai_response do |arg|
      arg.is_a?(Hash)
    end

    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    @topic.reload
    assert_equal 5, @topic.resident_impact_score

    mock_ai.verify
  end

  test "generates meeting summary from transcript when no minutes exist" do
    doc = @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.txt",
      extracted_text: "Transcript of meeting: The council discussed the budget at length."
    )

    generation_data = {
      "headline" => "Council discussed the budget",
      "highlights" => [
        { "text" => "Budget discussed", "citation" => "Transcript", "impact" => "medium" }
      ],
      "public_input" => [],
      "item_details" => [],
      "source_type" => "transcript"
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "transcript"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "transcript_recap")
    assert summary, "Should create a transcript_recap summary"
    assert_equal "transcript", summary.generation_data["source_type"]
    assert_nil @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
  end

  test "minutes take priority over transcript" do
    @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: The council approved the budget 5-2."
    )
    @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.txt",
      extracted_text: "Transcript of meeting: The council discussed the budget."
    )

    generation_data = {
      "headline" => "Council approved the budget",
      "highlights" => [
        { "text" => "Budget approved", "citation" => "Page 1", "vote" => "5-2", "impact" => "high" }
      ],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "minutes"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "minutes_recap")
    assert summary, "Should create minutes_recap"
    assert_equal "minutes_with_transcript", summary.generation_data["source_type"]
    assert_nil @meeting.meeting_summaries.find_by(summary_type: "transcript_recap"), "Should NOT create transcript_recap"
  end

  test "stores preview framing in generation_data for future meeting with packet" do
    @meeting.update!(starts_at: 3.days.from_now)

    @meeting.meeting_documents.create!(
      document_type: "packet_pdf",
      source_url: "http://example.com/packet.pdf",
      extracted_text: "Agenda: Budget review scheduled."
    )

    generation_data = {
      "headline" => "Council will consider the budget",
      "highlights" => [],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :prepare_doc_context, "Agenda text" do |arg| true end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "packet"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
    assert summary, "Should create a packet_analysis summary"
    assert_equal "preview", summary.generation_data["framing"]
  end

  test "same-day future meeting gets preview framing, not stale_preview" do
    # Meeting later today: same calendar date as Date.current, but hours away.
    # The old date-only comparison (meeting_date > today) resolved false for
    # same-day meetings and fell through to stale_preview, which told the AI
    # to use past tense ("was scheduled") for a meeting that hadn't happened.
    @meeting.update!(starts_at: 3.hours.from_now)

    @meeting.meeting_documents.create!(
      document_type: "packet_pdf",
      source_url: "http://example.com/packet.pdf",
      extracted_text: "Agenda: Budget review scheduled for later today."
    )

    generation_data = {
      "headline" => "Council will consider the budget",
      "highlights" => [],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :prepare_doc_context, "Agenda text" do |arg| true end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "packet"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "packet_analysis")
    assert summary
    assert_equal "preview", summary.generation_data["framing"],
      "Meeting that starts later today should be a preview, not a stale_preview"
  end

  test "cleans up packet_analysis when minutes_recap is created" do
    # Pre-existing packet preview
    @meeting.meeting_summaries.create!(
      summary_type: "packet_analysis",
      generation_data: { "headline" => "Old preview", "framing" => "preview" }
    )

    @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: The council approved the budget 5-2."
    )

    generation_data = {
      "headline" => "Council approved the budget",
      "highlights" => [],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "minutes"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    assert_nil @meeting.meeting_summaries.find_by(summary_type: "packet_analysis"),
      "packet_analysis should be cleaned up when minutes_recap arrives"
    assert @meeting.meeting_summaries.find_by(summary_type: "minutes_recap"),
      "minutes_recap should exist"
  end

  test "cleans up packet_analysis when transcript_recap is created" do
    @meeting.meeting_summaries.create!(
      summary_type: "packet_analysis",
      generation_data: { "headline" => "Old preview", "framing" => "stale_preview" }
    )

    @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.txt",
      extracted_text: "Transcript: The council discussed the budget."
    )

    generation_data = {
      "headline" => "Council discussed the budget",
      "highlights" => [],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **kwargs|
      type == "transcript"
    end
    # Topic-level mocks
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    assert_nil @meeting.meeting_summaries.find_by(summary_type: "packet_analysis"),
      "packet_analysis should be cleaned up when transcript_recap arrives"
    assert @meeting.meeting_summaries.find_by(summary_type: "transcript_recap"),
      "transcript_recap should exist"
  end

  test "enqueues ExtractKnowledgeJob after summarization" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: ExtractKnowledgeJob, args: [ @meeting.id ]) do
          SummarizeMeetingJob.perform_now(@meeting.id)
        end
      end
    end
  end

  test "enqueues GenerateTopicBriefingJob after topic summary generation" do
    mock_ai = Minitest::Mock.new
    # Meeting-level: prepare_kb_context called (no docs, so no analyze call)
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_summary, "## Topic Summary" do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: Topics::GenerateTopicBriefingJob) do
          SummarizeMeetingJob.perform_now(@meeting.id)
        end
      end
    end
  end

  test "defaults to :full mode when mode kwarg is omitted" do
    called = nil
    job = SummarizeMeetingJob.new
    job.define_singleton_method(:run_full_mode) { |_m| called = :full }
    job.define_singleton_method(:run_agenda_preview_mode) { |_m| called = :agenda_preview }

    job.perform(@meeting.id)
    assert_equal :full, called
  end

  test "dispatches to :agenda_preview when mode kwarg is :agenda_preview" do
    called = nil
    job = SummarizeMeetingJob.new
    job.define_singleton_method(:run_full_mode) { |_m| called = :full }
    job.define_singleton_method(:run_agenda_preview_mode) { |_m| called = :agenda_preview }

    job.perform(@meeting.id, mode: :agenda_preview)
    assert_equal :agenda_preview, called
  end

  test "raises on unknown mode" do
    job = SummarizeMeetingJob.new
    assert_raises(ArgumentError) do
      job.perform(@meeting.id, mode: :bogus)
    end
  end

  test "enqueues PruneHollowAppearancesJob after summarization" do
    doc = @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Page 1: routine content."
    )

    generation_data = {
      "headline" => "Routine",
      "highlights" => [],
      "public_input" => [],
      "item_details" => []
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_t, _k, type| type == "minutes" end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        assert_enqueued_with(job: PruneHollowAppearancesJob, args: [ @meeting.id ]) do
          SummarizeMeetingJob.perform_now(@meeting.id)
        end
      end
    end
  end

  test "agenda_preview mode generates meeting summary from agenda_pdf extracted_text" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Welcome. 2. Review of last meeting. 3. Discussion of playground repairs."
    )

    generation_data = {
      "headline" => "Board will review playground repairs tonight",
      "highlights" => [],
      "public_input" => [],
      "item_details" => [
        { "title" => "Playground repairs", "summary" => "The board will discuss playground repairs.", "activity_level" => "discussion" }
      ]
    }

    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg|
      arg.is_a?(Array)
    end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |text, kb, type, **|
      type == "agenda" && text.include?("playground")
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
      end
    end

    summary = @meeting.meeting_summaries.find_by(summary_type: "agenda_preview")
    assert summary, "Should create an agenda_preview summary"
    assert_equal "agenda", summary.generation_data["source_type"]
    assert_equal "Board will review playground repairs tonight", summary.generation_data["headline"]
    mock_ai.verify
  end

  test "agenda_preview mode returns silently when no agenda_pdf exists" do
    assert_nothing_raised do
      SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
    end
    assert_equal 0, @meeting.meeting_summaries.count
  end

  test "agenda_preview mode returns silently when agenda_pdf extracted_text is blank" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: ""
    )

    assert_nothing_raised do
      SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
    end
    assert_equal 0, @meeting.meeting_summaries.count
  end

  test "agenda_preview mode enqueues GenerateTopicBriefingJob for each approved topic" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Budget review."
    )

    generation_data = { "headline" => "H", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |*, **| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_enqueued_with(job: Topics::GenerateTopicBriefingJob, args: [ { topic_id: @topic.id, meeting_id: @meeting.id } ]) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
        end
      end
    end
  end

  test "agenda_preview mode does NOT create TopicSummary records" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Budget review."
    )

    generation_data = { "headline" => "H", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |*, **| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
      end
    end

    assert_equal 0, @meeting.topic_summaries.count
  end

  test "agenda_preview mode does NOT enqueue PruneHollowAppearancesJob or ExtractKnowledgeJob" do
    @meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      source_url: "http://example.com/agenda.pdf",
      extracted_text: "1. Budget review."
    )

    generation_data = { "headline" => "H", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |*, **| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_no_enqueued_jobs(only: [ PruneHollowAppearancesJob, ExtractKnowledgeJob ]) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          SummarizeMeetingJob.perform_now(@meeting.id, mode: :agenda_preview)
        end
      end
    end
  end

  test "packet run destroys any pre-existing agenda_preview summary" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview headline", "source_type" => "agenda" }
    )

    @meeting.meeting_documents.create!(
      document_type: "packet_pdf",
      source_url: "http://example.com/packet.pdf",
      extracted_text: "Packet body text."
    )

    generation_data = { "headline" => "Packet headline", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_text, _kb, type, **|
      type == "packet"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    refute @meeting.meeting_summaries.exists?(summary_type: "agenda_preview"),
      "packet run should destroy any pre-existing agenda_preview"
    assert @meeting.meeting_summaries.exists?(summary_type: "packet_analysis"),
      "packet_analysis should now exist"
  end

  test "transcript run destroys any pre-existing agenda_preview summary" do
    @meeting.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: { "headline" => "Agenda preview", "source_type" => "agenda" }
    )

    @meeting.meeting_documents.create!(
      document_type: "transcript",
      source_url: "http://example.com/transcript.srt",
      extracted_text: "Transcript text."
    )

    generation_data = { "headline" => "Transcript headline", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_text, _kb, type, **|
      type == "transcript"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    refute @meeting.meeting_summaries.exists?(summary_type: "agenda_preview"),
      "transcript run should destroy agenda_preview"
  end

  test "minutes run destroys pre-existing agenda_preview, packet_analysis, and transcript_recap" do
    @meeting.meeting_summaries.create!(summary_type: "agenda_preview", generation_data: { "headline" => "A" })
    @meeting.meeting_summaries.create!(summary_type: "packet_analysis", generation_data: { "headline" => "P" })
    @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: { "headline" => "T" })

    @meeting.meeting_documents.create!(
      document_type: "minutes_pdf",
      source_url: "http://example.com/minutes.pdf",
      extracted_text: "Minutes text."
    )

    generation_data = { "headline" => "Minutes headline", "highlights" => [], "public_input" => [], "item_details" => [] }
    mock_ai = Minitest::Mock.new
    mock_ai.expect :prepare_kb_context, "" do |arg| arg.is_a?(Array) end
    mock_ai.expect :analyze_meeting_content, generation_data.to_json do |_text, _kb, type, **|
      type == "minutes"
    end
    mock_ai.expect :analyze_topic_summary, '{"factual_record": []}' do |arg| arg.is_a?(Hash) end
    mock_ai.expect :render_topic_summary, "## Summary" do |arg| arg.is_a?(String) end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        SummarizeMeetingJob.perform_now(@meeting.id)
      end
    end

    refute @meeting.meeting_summaries.exists?(summary_type: "agenda_preview"), "minutes should destroy agenda_preview"
    refute @meeting.meeting_summaries.exists?(summary_type: "packet_analysis"), "minutes should destroy packet_analysis"
    refute @meeting.meeting_summaries.exists?(summary_type: "transcript_recap"), "minutes should destroy transcript_recap"
    assert @meeting.meeting_summaries.exists?(summary_type: "minutes_recap"), "minutes_recap should exist"
  end
end
