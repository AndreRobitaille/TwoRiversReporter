require "test_helper"

class Topics::GenerateTopicBriefingJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Downtown Parking", status: "approved")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
    @item = @meeting.agenda_items.create!(title: "Parking Plan Vote", order_index: 1)
    @item.topics << @topic
    @section = @meeting.agenda_items.create!(title: "PARKING", kind: "section", order_index: 0)
    AgendaItemTopic.create!(agenda_item: @section, topic: @topic)

    # Pre-existing per-meeting TopicSummary (the building block)
    @topic_summary = TopicSummary.create!(
      topic: @topic,
      meeting: @meeting,
      content: "## Parking\n- Council voted 4-3",
      summary_type: "topic_digest",
      generation_data: {
        "headline" => "Council approved parking plan 4-3",
        "factual_record" => [ { "statement" => "Approved 4-3", "citations" => [] } ]
      }
    )
  end

  test "generates full briefing from topic summary building blocks" do
    analysis_json = {
      "headline" => "Council approved modified parking plan 4-3 on Feb 18",
      "upcoming_headline" => nil,
      "editorial_analysis" => {
        "current_state" => "The city approved the plan.",
        "pattern_observations" => [ "Deferred twice" ],
        "process_concerns" => [],
        "what_to_watch" => nil
      },
      "factual_record" => [
        { "event" => "Approved 4-3", "date" => "2026-02-18", "citations" => [ "Minutes p.7" ] }
      ],
      "civic_sentiment" => [],
      "continuity_signals" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "The city just approved converting 8 spots...",
      "record_content" => "- Feb 18 — Approved 4-3 [Minutes p.7]"
    } do |arg|
      arg.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    briefing = @topic.reload.topic_briefing
    assert_not_nil briefing
    assert_equal "Council approved modified parking plan 4-3 on Feb 18", briefing.headline
    assert_nil briefing.upcoming_headline
    assert_includes briefing.editorial_content, "8 spots"
    assert_includes briefing.record_content, "Minutes p.7"
    assert_equal "full", briefing.generation_tier
    assert_not_nil briefing.last_full_generation_at
    assert_equal @meeting, briefing.triggering_meeting
    assert briefing.generation_data.key?("editorial_analysis")

    mock_ai.verify
  end

  test "saves upcoming_headline when AI provides one" do
    # Create a future meeting appearance
    future_meeting = Meeting.create!(
      body_name: "Plan Commission",
      starts_at: 5.days.from_now,
      detail_page_url: "http://example.com/future"
    )
    future_item = future_meeting.agenda_items.create!(title: "Parking Review", order_index: 1)
    # AgendaItemTopic#after_create callback creates the TopicAppearance.
    AgendaItemTopic.create!(topic: @topic, agenda_item: future_item)

    analysis_json = {
      "headline" => "Council approved parking plan 4-3",
      "upcoming_headline" => "Plan Commission reviews parking changes, Mar 5",
      "editorial_analysis" => { "current_state" => "Approved" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      # Verify upcoming_context is included
      arg.is_a?(Hash) && arg[:upcoming_context].is_a?(Array) && arg[:upcoming_context].any?
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Editorial", "record_content" => "Record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    briefing = @topic.reload.topic_briefing
    assert_equal "Plan Commission reviews parking changes, Mar 5", briefing.upcoming_headline
    mock_ai.verify
  end

  test "upcoming_context deduplicates meetings and excludes structural rows while keeping parent context" do
    future_meeting = Meeting.create!(
      body_name: "Plan Commission",
      starts_at: 5.days.from_now,
      detail_page_url: "http://example.com/future-2"
    )
    section = future_meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
    child = future_meeting.agenda_items.create!(title: "Parking Review", kind: "item", parent: section, order_index: 1)
    AgendaItemTopic.create!(topic: @topic, agenda_item: child)
    AgendaItemTopic.create!(topic: @topic, agenda_item: section)

    captured_context = nil
    analysis_json = {
      "headline" => "Council approved parking plan 4-3",
      "upcoming_headline" => "Plan Commission reviews parking changes, Mar 5",
      "editorial_analysis" => { "current_state" => "Approved" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      captured_context = arg
      true
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Editorial", "record_content" => "Record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    assert_equal 1, captured_context[:upcoming_context].length
    titles = captured_context[:upcoming_context].first[:agenda_items].map { |item| item[:title] }
    assert_includes titles, "NEW BUSINESS — Parking Review"
    refute_includes titles, "NEW BUSINESS"
    mock_ai.verify
  end

  test "briefing context ignores meetings where topic appears only on structural rows" do
    future_meeting = Meeting.create!(
      body_name: "Library Board",
      starts_at: 4.days.from_now,
      detail_page_url: "http://example.com/future-structural-only"
    )
    section = future_meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
    AgendaItemTopic.create!(topic: @topic, agenda_item: section)

    captured_context = nil
    analysis_json = {
      "headline" => "Council approved parking plan 4-3",
      "upcoming_headline" => nil,
      "editorial_analysis" => { "current_state" => "Approved" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      captured_context = arg
      true
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Editorial", "record_content" => "Record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    meeting_bodies = captured_context[:upcoming_context].map { |entry| entry[:meeting_body] }
    refute_includes meeting_bodies, "Library Board"
    mock_ai.verify
  end

  test "prior meeting analyses ignore topic summaries from section-only meetings" do
    section_only_meeting = Meeting.create!(
      body_name: "Library Board",
      starts_at: 2.days.ago,
      detail_page_url: "http://example.com/section-only-summary"
    )
    section = section_only_meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
    AgendaItemTopic.create!(topic: @topic, agenda_item: section)
    TopicSummary.create!(
      topic: @topic,
      meeting: section_only_meeting,
      content: "## Section only",
      summary_type: "topic_digest",
      generation_data: { "headline" => "Section only headline" }
    )

    captured_context = nil
    analysis_json = {
      "headline" => "Council approved parking plan 4-3",
      "upcoming_headline" => nil,
      "editorial_analysis" => { "current_state" => "Approved" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      captured_context = arg
      true
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Editorial", "record_content" => "Record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    headlines = captured_context[:prior_meeting_analyses].filter_map { |entry| entry["headline"] }
    refute_includes headlines, "Section only headline"
    mock_ai.verify
  end

  test "propagates resident impact score to topic" do
    analysis_json = {
      "headline" => "Test",
      "upcoming_headline" => nil,
      "editorial_analysis" => { "current_state" => "Test" },
      "factual_record" => [],
      "resident_impact" => { "score" => 4, "rationale" => "Test" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |_| true end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Test", "record_content" => "Test"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    assert_equal 4, @topic.reload.resident_impact_score
  end

  test "skips non-approved topics" do
    @topic.update!(status: "proposed")

    Topics::GenerateTopicBriefingJob.perform_now(
      topic_id: @topic.id,
      meeting_id: @meeting.id
    )

    assert_nil @topic.reload.topic_briefing
  end

  test "skips when topic has only structural agenda items for the meeting" do
    section_only_topic = Topic.create!(name: "Section Only Topic", status: "approved")
    section_only_meeting = Meeting.create!(
      body_name: "Library Board",
      starts_at: 2.days.from_now,
      detail_page_url: "http://example.com/section-only-briefing"
    )
    section = section_only_meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
    AgendaItemTopic.create!(topic: section_only_topic, agenda_item: section)

    assert_nothing_raised do
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: section_only_topic.id, meeting_id: section_only_meeting.id)
    end

    assert_nil section_only_topic.reload.topic_briefing
  end

  test "falls back to latest substantive meeting when triggering meeting is structural only" do
    fallback_meeting = Meeting.create!(
      body_name: "Plan Commission",
      starts_at: 3.days.ago,
      detail_page_url: "http://example.com/fallback-substantive"
    )
    fallback_item = fallback_meeting.agenda_items.create!(title: "Parking Ramp Expansion", order_index: 1)
    AgendaItemTopic.create!(topic: @topic, agenda_item: fallback_item)

    structural_meeting = Meeting.create!(
      body_name: "Library Board",
      starts_at: 1.day.from_now,
      detail_page_url: "http://example.com/structural-trigger"
    )
    structural_section = structural_meeting.agenda_items.create!(title: "NEW BUSINESS", kind: "section", order_index: 0)
    AgendaItemTopic.create!(topic: @topic, agenda_item: structural_section)

    captured_context = nil
    analysis_json = {
      "headline" => "Council approved parking plan 4-3",
      "upcoming_headline" => nil,
      "editorial_analysis" => { "current_state" => "Approved" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Affects downtown" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      captured_context = arg
      true
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "Editorial", "record_content" => "Record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: structural_meeting.id
        )
      end
    end

    assert captured_context[:recent_raw_context].map { |entry| entry[:title] }.any? { |title| title == "Parking Plan Vote" || title == "Parking Ramp Expansion" }
    refute_equal structural_meeting, @topic.reload.topic_briefing.triggering_meeting
    mock_ai.verify
  end

  test "context passed to analyze_topic_briefing includes recent_item_details from linked agenda items" do
    # Attach a MeetingSummary with item_details for the linked agenda item
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "Parking Plan Vote",
            "summary" => "Council converted 8 downtown spots to 15-minute loading.",
            "activity_level" => "discussion",
            "vote" => "4-3",
            "decision" => nil,
            "public_hearing" => nil
          }
        ]
      }
    )

    captured_context = nil
    analysis_json = {
      "headline" => "h", "upcoming_headline" => nil,
      "editorial_analysis" => { "current_state" => "c" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "r" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      captured_context = arg
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "e", "record_content" => "r"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    assert captured_context.key?(:recent_item_details),
      "briefing context must include :recent_item_details key"
    assert_kind_of Array, captured_context[:recent_item_details]
    assert_equal 1, captured_context[:recent_item_details].length
    entry = captured_context[:recent_item_details].first
    assert_equal "Parking Plan Vote", entry[:agenda_item_title]
    assert_includes entry[:summary], "15-minute loading"
    assert_equal "4-3", entry[:vote]

    mock_ai.verify
  end

  test "context passed to analyze_topic_briefing excludes structural agenda rows" do
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "item_details" => [
          {
            "agenda_item_title" => "PARKING",
            "summary" => "Section header only.",
            "activity_level" => "discussion"
          },
          {
            "agenda_item_title" => "Parking Plan Vote",
            "summary" => "Council converted 8 downtown spots.",
            "activity_level" => "decision"
          }
        ]
      }
    )

    captured_context = nil
    analysis_json = {
      "headline" => "h", "upcoming_headline" => nil,
      "editorial_analysis" => { "current_state" => "c" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "r" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |arg|
      captured_context = arg
      arg.is_a?(Hash)
    end
    mock_ai.expect :render_topic_briefing, { "editorial_content" => "e", "record_content" => "r" } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      end
    end

    assert_equal 1, captured_context[:recent_item_details].length
    assert_equal "Parking Plan Vote", captured_context[:recent_item_details].first[:agenda_item_title]
    assert_equal 1, captured_context[:continuity_context][:total_appearances]
    mock_ai.verify
  end

  test "is idempotent — updates existing briefing" do
    TopicBriefing.create!(
      topic: @topic,
      headline: "Old headline",
      generation_tier: "interim"
    )

    analysis_json = {
      "headline" => "New headline",
      "upcoming_headline" => "Coming up soon",
      "editorial_analysis" => { "current_state" => "Updated" },
      "factual_record" => [],
      "resident_impact" => { "score" => 3, "rationale" => "Test" }
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :analyze_topic_briefing, analysis_json do |_| true end
    mock_ai.expect :render_topic_briefing, {
      "editorial_content" => "New editorial", "record_content" => "New record"
    } do |_| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: @topic.id,
          meeting_id: @meeting.id
        )
      end
    end

    assert_equal 1, TopicBriefing.where(topic: @topic).count
    assert_equal "New headline", @topic.reload.topic_briefing.headline
    assert_equal "Coming up soon", @topic.reload.topic_briefing.upcoming_headline
  end
end
