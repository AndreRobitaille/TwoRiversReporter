require "test_helper"
require "securerandom"

class Topics::MeetingReanalysisServiceTest < ActiveSupport::TestCase
  test "parse error leaves links summaries and appearances intact" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    topic = Topic.create!(name: "city budget", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    appearance = TopicAppearance.find_by!(topic: topic, meeting: meeting, agenda_item: item)
    summary = TopicSummary.create!(topic: topic, meeting: meeting, content: "stale", summary_type: "topic_digest", generation_data: { "stale" => true })
    meeting.update!(processing_state: { "topics_extraction_status" => "processed" })

    ai_service = Object.new
    ai_service.define_singleton_method(:analyze_topic_summary) { raise "should not run" }
    ai_service.define_singleton_method(:render_topic_summary) { raise "should not run" }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    before_link_count = AgendaItemTopic.count

    assert_raises(RuntimeError) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, ai_service do
          ExtractTopicsJob.stub :perform_now, ->(_meeting_id) { meeting.update!(processing_state: meeting.processing_state.merge("topics_extraction_status" => "parse_error")) } do
            Topics::MeetingReanalysisService.new(meeting.id).call
          end
        end
      end
    end

    assert_equal before_link_count, AgendaItemTopic.count
    assert AgendaItemTopic.exists?(agenda_item: item, topic: topic)
    assert TopicAppearance.exists?(appearance.id)
    assert TopicSummary.exists?(summary.id)
  end

  test "empty after topics raises unless allowed" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    topic = Topic.create!(name: "city budget", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    meeting.update!(processing_state: { "topics_extraction_status" => "processed" })

    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **_kwargs| { "items" => [] }.to_json }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    error = assert_raises(RuntimeError) do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::MeetingReanalysisService.new(meeting.id, allow_empty_topics: false).call
        end
      end
    end

    assert_match(/Empty topic set/, error.message)
    assert AgendaItemTopic.exists?(agenda_item: item, topic: topic)
  end

  test "topic relinked by extraction remains in after ids" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: meeting.starts_at)
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    meeting.update!(processing_state: { "topics_extraction_status" => "processed" })

    extract_response = { "items" => [ { "id" => item.id, "category" => "Finance", "tags" => [ "room tax budget" ], "topic_worthy" => true, "confidence" => 0.9 } ] }.to_json
    summary_response = { "headline" => "Room tax budget review is upcoming", "factual_record" => [], "resident_impact" => { "score" => 2, "rationale" => "Commission-specific budget review" } }.to_json

    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **_kwargs| extract_response }
    mock_ai.define_singleton_method(:analyze_topic_summary) { |_context, **_kwargs| summary_response }
    mock_ai.define_singleton_method(:render_topic_summary) { |_analysis_json, **_kwargs| "summary" }
    mock_ai.define_singleton_method(:analyze_topic_briefing) { |_context, **_kwargs| { "headline" => "headline", "factual_record" => [], "resident_impact" => { "score" => 2 } }.to_json }
    mock_ai.define_singleton_method(:render_topic_briefing) { |_analysis_json, **_kwargs| { "editorial_content" => "Editorial", "record_content" => "Record" } }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    result = nil
    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { true } do
          result = Topics::MeetingReanalysisService.new(meeting.id).call
        end
      end
    end

    assert_equal [ topic.id ], result.after_topic_ids
    assert_equal [ topic.id ], item.reload.topics.pluck(:id)
  end

  test "stale topic appearance and non digest summaries are handled correctly" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    old_topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: meeting.starts_at)
    new_topic = Topic.create!(name: "zoning change", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: old_topic)
    TopicAppearance.find_by!(topic: old_topic, meeting: meeting, agenda_item: item)
    kept_summary = TopicSummary.create!(topic: old_topic, meeting: meeting, content: "keep", summary_type: "meeting_digest", generation_data: { "seed" => true })
    TopicSummary.create!(topic: old_topic, meeting: meeting, content: "stale", summary_type: "topic_digest", generation_data: { "stale" => true })

    extract_response = { "items" => [ { "id" => item.id, "category" => "Finance", "tags" => [ "room tax budget" ], "topic_worthy" => true, "confidence" => 0.9 } ] }.to_json
    summary_response = { "headline" => "Room tax budget review is upcoming", "factual_record" => [], "resident_impact" => { "score" => 2, "rationale" => "Commission-specific budget review" } }.to_json
    briefing_response = { "headline" => "Room tax budget review is upcoming", "editorial_analysis" => { "current_state" => "Upcoming commission budget review" }, "factual_record" => [], "resident_impact" => { "score" => 2, "rationale" => "Commission-specific" } }.to_json

    briefing_topic_ids = []
    continuity_topic_ids = []
    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **kwargs| raise "missing meeting context" unless kwargs[:meeting_context].include?("Room Tax Commission"); extract_response }
    mock_ai.define_singleton_method(:analyze_topic_summary) do |context, **_kwargs|
      raise "unexpected summary topic" unless [ old_topic.id, new_topic.id ].include?(context[:topic_metadata][:id])
      summary_response
    end
    mock_ai.define_singleton_method(:render_topic_summary) { |_analysis_json, **_kwargs| "## Room tax budget\nCommission budget review" }
    mock_ai.define_singleton_method(:analyze_topic_briefing) { |context, **_kwargs| briefing_topic_ids << context[:topic_metadata][:id]; briefing_response }
    mock_ai.define_singleton_method(:render_topic_briefing) { |_analysis_json, **_kwargs| { "editorial_content" => "Editorial", "record_content" => "Record" } }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    GeneratedImages::HomepageTopicSelector.stub :new, -> { [ new_topic ] } do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::UpdateContinuityJob.stub :perform_now, ->(topic_id:) { continuity_topic_ids << topic_id } do
            Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { briefing_topic_ids << topic_id } do
              Topics::MeetingReanalysisService.new(meeting.id).call
            end
          end
        end
      end
    end

    item.reload
    assert_equal [ old_topic.id ], item.topics.pluck(:id)
    assert_equal 2, old_topic.reload.resident_impact_score
    assert TopicAppearance.exists?(topic: old_topic, meeting: meeting, agenda_item: item)
    assert TopicSummary.exists?(kept_summary.id)
    assert TopicSummary.find_by(topic: old_topic, meeting: meeting, summary_type: "topic_digest")
    assert_equal [ old_topic.id ], continuity_topic_ids.sort
    assert_equal [ old_topic.id ], briefing_topic_ids.sort
  end

  test "topic moved between agenda items removes stale appearance without deleting topic summary" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item_a = AgendaItem.create!(meeting: meeting, title: "ITEM A", order_index: 1, kind: "item")
    item_b = AgendaItem.create!(meeting: meeting, title: "ITEM B", order_index: 2, kind: "item")
    topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: meeting.starts_at)
    AgendaItemTopic.create!(agenda_item: item_a, topic: topic)
    TopicSummary.create!(topic: topic, meeting: meeting, content: "keep", summary_type: "topic_digest", generation_data: { "seed" => true })

    extract_response = { "items" => [
      { "id" => item_a.id, "category" => "Finance", "tags" => [], "topic_worthy" => true, "confidence" => 0.9 },
      { "id" => item_b.id, "category" => "Finance", "tags" => [ "room tax budget" ], "topic_worthy" => true, "confidence" => 0.9 }
    ] }.to_json
    summary_response = { "headline" => "Room tax budget moved", "factual_record" => [], "resident_impact" => { "score" => 2, "rationale" => "Moved item" } }.to_json

    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **_kwargs| extract_response }
    mock_ai.define_singleton_method(:analyze_topic_summary) { |_context, **_kwargs| summary_response }
    mock_ai.define_singleton_method(:render_topic_summary) { |_analysis_json, **_kwargs| "summary" }
    mock_ai.define_singleton_method(:analyze_topic_briefing) { |_context, **_kwargs| { "headline" => "headline", "factual_record" => [], "resident_impact" => { "score" => 2 } }.to_json }
    mock_ai.define_singleton_method(:render_topic_briefing) { |_analysis_json, **_kwargs| { "editorial_content" => "Editorial", "record_content" => "Record" } }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    GeneratedImages::HomepageTopicSelector.stub :new, -> { [ topic ] } do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::UpdateContinuityJob.stub :perform_now, ->(topic_id:) { true } do
            Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { true } do
              Topics::MeetingReanalysisService.new(meeting.id).call
            end
          end
        end
      end
    end

    assert_not TopicAppearance.exists?(topic: topic, meeting: meeting, agenda_item: item_a)
    assert TopicAppearance.exists?(topic: topic, meeting: meeting, agenda_item: item_b)
    assert TopicSummary.exists?(topic: topic, meeting: meeting, summary_type: "topic_digest")
  end

  test "rollback removes partially created extraction links and appearances before restoring old ones" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    old_topic = Topic.create!(name: "city budget", status: "approved", review_status: "approved")
    new_topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: old_topic)

    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **_kwargs| { "items" => [ { "id" => item.id, "category" => "Finance", "tags" => [ "room tax budget" ], "topic_worthy" => true, "confidence" => 0.9 } ] }.to_json }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    ExtractTopicsJob.stub :perform_now, ->(_meeting_id) do
      AgendaItemTopic.create!(agenda_item: item, topic: new_topic)
      meeting.update!(processing_state: meeting.processing_state.merge("topics_extraction_status" => "parse_error"))
    end do
      error = assert_raises(RuntimeError) do
        RetrievalService.stub :new, retrieval_stub do
          Ai::OpenAiService.stub :new, mock_ai do
            Topics::MeetingReanalysisService.new(meeting.id).call
          end
        end
      end

      assert_match(/Topic extraction failed/, error.message)
    end

    assert_equal [ old_topic.id ], item.reload.topics.pluck(:id)
    assert_not item.topics.exists?(new_topic.id)
    assert_not TopicAppearance.exists?(topic: new_topic, meeting: meeting, agenda_item: item)
  end

  test "stale topic status events tied to removed appearances are cleaned up even when topic remains elsewhere" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item_a = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    item_b = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW 2", order_index: 2, kind: "item")
    old_topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved", resident_impact_score: 4, last_activity_at: meeting.starts_at)
    new_topic = Topic.create!(name: "zoning change", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item_a, topic: old_topic)
    AgendaItemTopic.create!(agenda_item: item_b, topic: old_topic)
    appearance = TopicAppearance.find_by!(topic: old_topic, meeting: meeting, agenda_item: item_a)

    stale_event = TopicStatusEvent.create!(
      topic: old_topic,
      lifecycle_status: "active",
      evidence_type: "cross_body_progression",
      occurred_at: meeting.starts_at,
      source_ref: { "appearance_id" => appearance.id }
    )
    preserved_event = TopicStatusEvent.create!(
      topic: old_topic,
      lifecycle_status: "active",
      evidence_type: "cross_body_progression",
      occurred_at: meeting.starts_at,
      source_ref: { "meeting_id" => meeting.id }
    )

    extract_response = { "items" => [
      { "id" => item_a.id, "category" => "Finance", "tags" => [ "zoning change" ], "topic_worthy" => true, "confidence" => 0.9 },
      { "id" => item_b.id, "category" => "Finance", "tags" => [ "room tax budget" ], "topic_worthy" => true, "confidence" => 0.9 }
    ] }.to_json
    summary_response = { "headline" => "Room tax budget review is upcoming", "factual_record" => [], "resident_impact" => { "score" => 2, "rationale" => "Commission-specific budget review" } }.to_json

    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **_kwargs| extract_response }
    mock_ai.define_singleton_method(:analyze_topic_summary) { |_context, **_kwargs| summary_response }
    mock_ai.define_singleton_method(:render_topic_summary) { |_analysis_json, **_kwargs| "summary" }
    mock_ai.define_singleton_method(:analyze_topic_briefing) { |_context, **_kwargs| { "headline" => "headline", "factual_record" => [], "resident_impact" => { "score" => 2 } }.to_json }
    mock_ai.define_singleton_method(:render_topic_briefing) { |_analysis_json, **_kwargs| { "editorial_content" => "Editorial", "record_content" => "Record" } }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    result = nil
    GeneratedImages::HomepageTopicSelector.stub :new, -> { [ new_topic ] } do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::UpdateContinuityJob.stub :perform_now, ->(topic_id:) { true } do
            Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { true } do
              result = Topics::MeetingReanalysisService.new(meeting.id).call
            end
          end
        end
      end
    end

    assert_includes result.after_topic_ids, old_topic.id
    assert_includes result.after_topic_ids, new_topic.id
    assert_not TopicStatusEvent.exists?(stale_event.id)
    assert TopicStatusEvent.exists?(preserved_event.id)
    assert_not TopicAppearance.exists?(topic: old_topic, meeting: meeting, agenda_item: item_a)
    assert TopicAppearance.exists?(topic: old_topic, meeting: meeting, agenda_item: item_b)
  end

  test "reused topic gets continuity and briefing once" do
    meeting = Meeting.create!(body_name: "Room Tax Commission Meeting", meeting_type: "regular", starts_at: Time.zone.parse("2026-06-23 16:00:00"), status: "upcoming", detail_page_url: "http://example.com/rtc")
    item = AgendaItem.create!(meeting: meeting, title: "BUDGET REVIEW", order_index: 1, kind: "item")
    topic = Topic.create!(name: "room tax budget", status: "approved", review_status: "approved")
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    meeting.update!(processing_state: { "topics_extraction_status" => "processed" })

    extract_response = { "items" => [ { "id" => item.id, "category" => "Finance", "tags" => [ "room tax budget" ], "topic_worthy" => true, "confidence" => 0.9 } ] }.to_json
    summary_response = { "headline" => "Room tax budget review is upcoming", "factual_record" => [], "resident_impact" => { "score" => 2, "rationale" => "Commission-specific budget review" } }.to_json

    mock_ai = Object.new
    mock_ai.define_singleton_method(:extract_topics) { |_text, **_kwargs| extract_response }
    mock_ai.define_singleton_method(:analyze_topic_summary) { |_context, **_kwargs| summary_response }
    mock_ai.define_singleton_method(:render_topic_summary) { |_analysis_json, **_kwargs| "summary" }
    mock_ai.define_singleton_method(:analyze_topic_briefing) { |_context, **_kwargs| { "headline" => "headline", "factual_record" => [], "resident_impact" => { "score" => 2 } }.to_json }
    mock_ai.define_singleton_method(:render_topic_briefing) { |_analysis_json, **_kwargs| { "editorial_content" => "Editorial", "record_content" => "Record" } }

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end
    def retrieval_stub.retrieve_topic_context(*args, **kwargs); []; end
    def retrieval_stub.format_topic_context(*args); []; end

    continuity_topic_ids = []
    briefing_topic_ids = []
    GeneratedImages::HomepageTopicSelector.stub :new, -> { [ topic ] } do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          Topics::UpdateContinuityJob.stub :perform_now, ->(topic_id:) { continuity_topic_ids << topic_id } do
            Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { briefing_topic_ids << topic_id } do
              result = Topics::MeetingReanalysisService.new(meeting.id).call

              assert_equal [ topic.id ], result.after_topic_ids
              assert_equal [ topic.id ], result.affected_topic_ids
            end
          end
        end
      end
    end

    assert_equal [ topic.id ], continuity_topic_ids
    assert_equal [ topic.id ], briefing_topic_ids
  end

  test "missing affected topic ids are skipped during briefing regeneration" do
    meeting = Meeting.create!(body_name: "City Council Work Session", meeting_type: "work_session", starts_at: Time.zone.parse("2026-06-29 18:00:00"), status: "upcoming", detail_page_url: "http://example.com/work-session")
    item = AgendaItem.create!(meeting: meeting, title: "WASTEWATER PLANNING", order_index: 1, kind: "item")
    topic = Topic.create!(name: "wastewater planning", status: "approved", review_status: "approved")
    missing_topic_id = Topic.maximum(:id).to_i + 100
    AgendaItemTopic.create!(agenda_item: item, topic: topic)
    meeting.update!(processing_state: { "topics_extraction_status" => "processed" })

    briefing_topic_ids = []
    service = Topics::MeetingReanalysisService.new(meeting.id)

    Topics::GenerateTopicBriefingJob.stub :perform_now, ->(topic_id:, meeting_id:) { Topic.find(topic_id); briefing_topic_ids << topic_id } do
      service.send(:regenerate_briefings, meeting, [ topic.id, missing_topic_id ])
    end

    assert_equal [ topic.id ], briefing_topic_ids
  end
end
