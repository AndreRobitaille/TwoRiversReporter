require "test_helper"

class GeneratedImages::ContentFingerprintTest < ActiveSupport::TestCase
  test "meeting fingerprint changes when summary content changes" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "agenda_preview",
      content: "",
      generation_data: { "headline" => "A", "highlights" => [ { "text" => "One" } ] }
    )

    first = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)
    summary.update!(generation_data: { "headline" => "B", "highlights" => [ { "text" => "Two" } ] })
    second = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)

    assert_not_equal first, second
  end

  test "meeting fingerprint does not change on touch without content change" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-touch")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "minutes_recap",
      content: "Minutes recap content",
      generation_data: { "headline" => "Headline", "highlights" => [ { "text" => "One" } ] }
    )

    first = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)
    summary.touch
    second = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)

    assert_equal first, second
  end

  test "meeting fingerprint changes when content field changes" do
    meeting = Meeting.create!(body_name: "Council", starts_at: Time.current, detail_page_url: "http://example.com/meeting-10")
    summary = MeetingSummary.create!(
      meeting: meeting,
      summary_type: "agenda_preview",
      content: "First content line with a substantive policy change.",
      generation_data: {}
    )

    first = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)
    summary.update!(content: "Second content line with a different substantive policy change.")
    second = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)

    assert_not_equal first, second
  end

  test "topic fingerprint uses briefing content" do
    topic = Topic.create!(name: "fingerprint topic", status: "approved", reuse_strategy: "canonical")
    briefing = TopicBriefing.create!(
      topic: topic,
      headline: "Residents will watch sidewalk bills",
      generation_tier: "full",
      generation_data: { "editorial_analysis" => { "what_to_watch" => "Assessments" } },
      editorial_content: "Editorial",
      record_content: "Record"
    )

    assert_match(/\A[a-f0-9]{64}\z/, GeneratedImages::ContentFingerprint.for_topic_briefing(briefing))
  end

  test "topic fingerprint changes when editorial or record content changes" do
    topic = Topic.create!(name: "fingerprint topic two", status: "approved", reuse_strategy: "canonical")
    briefing = TopicBriefing.create!(
      topic: topic,
      headline: "Residents will watch sidewalk bills",
      generation_tier: "full",
      generation_data: { "editorial_analysis" => { "what_to_watch" => "Assessments" } },
      editorial_content: "Editorial one",
      record_content: "Record one"
    )

    first = GeneratedImages::ContentFingerprint.for_topic_briefing(briefing)
    briefing.update!(editorial_content: "Editorial two")
    second = GeneratedImages::ContentFingerprint.for_topic_briefing(briefing)
    briefing.update!(record_content: "Record two")
    third = GeneratedImages::ContentFingerprint.for_topic_briefing(briefing)

    assert_not_equal first, second
    assert_not_equal second, third
  end

  test "topic fingerprint does not change on touch without content change" do
    topic = Topic.create!(name: "fingerprint topic three", status: "approved", reuse_strategy: "canonical")
    briefing = TopicBriefing.create!(
      topic: topic,
      headline: "Residents will watch sidewalk bills",
      generation_tier: "full",
      generation_data: { "editorial_analysis" => { "what_to_watch" => "Assessments" } },
      editorial_content: "Editorial one",
      record_content: "Record one"
    )

    first = GeneratedImages::ContentFingerprint.for_topic_briefing(briefing)
    briefing.touch
    second = GeneratedImages::ContentFingerprint.for_topic_briefing(briefing)

    assert_equal first, second
  end
end
