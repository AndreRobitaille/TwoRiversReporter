require "test_helper"

class Ai::OpenAiServiceBriefingTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "analyze_topic_briefing sends request and returns content" do
    context = {
      topic_metadata: { canonical_name: "Downtown Parking", lifecycle_status: "active" },
      prior_meeting_analyses: [ { "headline" => "Prior meeting headline" } ],
      recent_raw_context: [],
      knowledgebase_context: [],
      continuity_context: { status_events: [], total_appearances: 3 }
    }

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => {
            "headline" => "Test headline",
            "editorial_analysis" => { "current_state" => "Test" },
            "factual_record" => [],
            "resident_impact" => { "score" => 3, "rationale" => "Test" }
          }.to_json
        }
      } ]
    }

    @service.instance_variable_get(:@client).stub :chat, mock_response do
      result = @service.analyze_topic_briefing(context)
      parsed = JSON.parse(result)
      assert parsed.key?("headline")
      assert parsed.key?("editorial_analysis")
    end
  end

  test "render_topic_briefing returns hash with editorial and record content" do
    analysis_json = {
      "headline" => "Test headline",
      "editorial_analysis" => { "current_state" => "The city approved..." },
      "factual_record" => [ { "event" => "Approved 4-3", "date" => "2026-02-18" } ]
    }.to_json

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => {
            "editorial_content" => "The city just approved...",
            "record_content" => "- Feb 18 — Approved 4-3"
          }.to_json
        }
      } ]
    }

    @service.instance_variable_get(:@client).stub :chat, mock_response do
      result = @service.render_topic_briefing(analysis_json)
      assert_equal "The city just approved...", result["editorial_content"]
      assert_equal "- Feb 18 — Approved 4-3", result["record_content"]
    end
  end

  test "render_topic_briefing returns empty hash on parse error" do
    bad_response = {
      "choices" => [ {
        "message" => { "content" => "not valid json {{{" }
      } ]
    }

    @service.instance_variable_get(:@client).stub :chat, bad_response do
      result = @service.render_topic_briefing("{}")
      assert_equal "", result["editorial_content"]
      assert_equal "", result["record_content"]
    end
  end

  test "generate_briefing_interim returns hash with headline and upcoming_note" do
    context = {
      topic_name: "Downtown Parking",
      current_headline: "Coming up at Council",
      meeting_body: "City Council",
      meeting_date: "2026-03-04",
      agenda_items: [ { title: "Parking Plan Vote" } ]
    }

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => {
            "headline" => "Council to vote on parking plan, Mar 4",
            "upcoming_note" => "The revised plan reduces conversion to 8 spots."
          }.to_json
        }
      } ]
    }

    @service.instance_variable_get(:@client).stub :chat, mock_response do
      result = @service.generate_briefing_interim(context)
      assert_equal "Council to vote on parking plan, Mar 4", result["headline"]
      assert_includes result["upcoming_note"], "revised plan"
    end
  end

  test "generate_briefing_interim returns fallback on parse error" do
    context = {
      topic_name: "Test",
      current_headline: "Fallback headline",
      meeting_body: "Council",
      meeting_date: "2026-03-04",
      agenda_items: []
    }

    bad_response = {
      "choices" => [ {
        "message" => { "content" => "broken json" }
      } ]
    }

    @service.instance_variable_get(:@client).stub :chat, bad_response do
      result = @service.generate_briefing_interim(context)
      assert_equal "Fallback headline", result["headline"]
      assert_equal "", result["upcoming_note"]
    end
  end
end
