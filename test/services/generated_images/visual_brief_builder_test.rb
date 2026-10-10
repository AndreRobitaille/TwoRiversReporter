require "test_helper"

class GeneratedImages::VisualBriefBuilderTest < ActiveSupport::TestCase
  test "meeting source without highlights includes headline item details and legacy content" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/meeting-brief", starts_at: Time.current)
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "Legacy fallback content",
      generation_data: {
        "headline" => "Headline text",
        "highlights" => [],
        "item_details" => [ { "summary" => "Item detail one" }, { "summary" => "Item detail two" } ]
      }
    )

    service = Minitest::Mock.new
    service.expect(:build_generated_image_brief, { "civic_issue" => "x", "composition" => "y", "avoid" => [] }) do |args|
      assert_equal "Meeting", args[:imageable_type]
      assert_includes args[:source_text], "Headline text"
      assert_includes args[:source_text], "Item detail one"
      assert_includes args[:source_text], "Item detail two"
      assert_includes args[:source_text], "Legacy fallback content"
      assert_includes args[:source_text], "one dominant resident-visible physical anchor"
      assert_includes args[:source_text], "cropped, non-identifying details"
      assert_equal false, args[:composite]
    end

    GeneratedImages::VisualBriefBuilder.new(meeting, source: summary, ai_service: service).call
    service.verify
  end

  test "meeting image uses the highest impact issue without blending unrelated agenda business" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/residency-brief", starts_at: Time.current)
    primary_issue = "Council will consider replacing the citywide sex-offender residency ban with a 1,000-foot protected-location rule."
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "agenda_preview",
      content: "Urban forestry grant and sex-offender residency ordinance",
      generation_data: {
        "headline" => "Council considers a tree-care grant and residency rules",
        "highlights" => [
          { "text" => "Apply for an urban forestry grant for tree planting", "impact" => "medium" },
          { "text" => primary_issue, "impact" => "high" }
        ],
        "item_details" => [ { "summary" => "Tree planting and nursery improvements" } ]
      }
    )
    service = Minitest::Mock.new
    service.expect(:build_generated_image_brief, {}) do |args|
      assert_includes args[:source_text], primary_issue
      assert_includes args[:source_text], "Illustrate only this issue"
      assert_includes args[:source_text], "do not imply that any depicted home houses an offender"
      refute_match(/forestry|tree-care|tree planting|nursery/i, args[:source_text])
      true
    end

    GeneratedImages::VisualBriefBuilder.new(meeting, source: summary, ai_service: service).call
    service.verify
  end

  test "legacy highlights without impact retain source order and ignore blank highlights" do
    meeting = Meeting.create!(detail_page_url: "http://example.com/legacy-brief", starts_at: Time.current)
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      generation_data: {
        "highlights" => [
          { "text" => "", "impact" => "high" },
          { "text" => "First substantive issue" },
          { "text" => "Second issue" }
        ]
      }
    )
    service = Minitest::Mock.new
    service.expect(:build_generated_image_brief, {}) do |args|
      assert_includes args[:source_text], "First substantive issue"
      refute_includes args[:source_text], "Second issue"
      true
    end

    GeneratedImages::VisualBriefBuilder.new(meeting, source: summary, ai_service: service).call
    service.verify
  end

  test "topic source text includes headline upcoming generation data and fallback content" do
    topic = Topic.create!(name: "Brief Topic", status: "approved")
    briefing = TopicBriefing.create!(
      topic: topic,
      headline: "Headline text",
      upcoming_headline: "Coming up text",
      editorial_content: "Editorial fallback",
      record_content: "Record fallback",
      generation_tier: "full",
      generation_data: {
        "editorial_analysis" => { "current_state" => "Analysis current state" },
        "factual_record" => [ { "date" => "2026-01-01", "event" => "Event one" } ]
      }
    )

    service = Minitest::Mock.new
    service.expect(:build_generated_image_brief, { "civic_issue" => "x", "composition" => "y", "avoid" => [] }) do |args|
      assert_equal "Topic", args[:imageable_type]
      assert_includes args[:source_text], "Headline text"
      assert_includes args[:source_text], "Coming up text"
      assert_includes args[:source_text], "Analysis current state"
      assert_includes args[:source_text], "Event one"
      assert_includes args[:source_text], "Editorial fallback"
      assert_includes args[:source_text], "Record fallback"
      assert_includes args[:source_text], "one dominant resident-visible physical anchor"
      assert_equal false, args[:composite]
    end

    GeneratedImages::VisualBriefBuilder.new(topic, source: briefing, ai_service: service).call
    service.verify
  end

  test "passes composite flag through" do
    topic = Topic.create!(name: "Composite Topic", status: "approved")
    briefing = TopicBriefing.create!(topic: topic, headline: "Headline", editorial_content: "Editorial", record_content: "Record", generation_tier: "full")
    eligibility = Struct.new(:composite?)

    service = Minitest::Mock.new
    service.expect(:build_generated_image_brief, { "civic_issue" => "x", "composition" => "y", "avoid" => [] }) do |args|
      assert_equal true, args[:composite]
    end

    GeneratedImages::VisualBriefBuilder.new(topic, source: briefing, eligibility: eligibility.new(true), ai_service: service).call
    service.verify
  end
end
