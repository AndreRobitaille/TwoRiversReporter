require "test_helper"

class OpenAiServiceAnalyzeMeetingTest < ActiveSupport::TestCase
  setup do
    seed_prompt_templates
    @service = Ai::OpenAiService.new
  end

  test "analyze_meeting_content prompt includes json keyword for response_format" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [ {
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        } ]
      }
    end

    result = nil
    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      result = @service.send(:analyze_meeting_content, "Test minutes text", "kb context", "minutes")
    end

    # Verify return value structure
    assert result.present?
    parsed = JSON.parse(result)
    assert parsed.key?("headline")
    assert parsed.key?("highlights")
    assert parsed.key?("public_input")
    assert parsed.key?("item_details")

    # Verify prompt content
    messages = captured_params[:messages]
    prompt_text = messages.map { |m| m[:content] }.join(" ")

    # Must contain "json" for OpenAI json_object mode
    assert prompt_text.downcase.include?("json"), "Prompt must contain 'json'"

    # Must request the new schema fields
    assert prompt_text.include?("headline"), "Prompt must request headline"
    assert prompt_text.include?("highlights"), "Prompt must request highlights"
    assert prompt_text.include?("public_input"), "Prompt must request public_input"
    assert prompt_text.include?("item_details"), "Prompt must request item_details"

    # Must mention editorial voice / plain language
    assert prompt_text.include?("plain language") || prompt_text.include?("editorial"),
      "Prompt must specify editorial voice"

    # Must exclude procedural items
    assert prompt_text.include?("procedural") || prompt_text.include?("adjourn"),
      "Prompt must mention procedural filtering"
  end

  test "analyze_meeting_content includes body_name in prompt to scope content extraction" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [ {
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        } ]
      }
    end

    meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: Time.current, detail_page_url: "https://example.com/meeting/1")

    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      @service.send(:analyze_meeting_content, "Test packet text", "kb context", "packet", source: meeting)
    end

    prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

    # Must include the body name so AI knows which meeting's content to extract
    assert prompt_text.include?("City Council Meeting"),
      "Prompt must include body_name to scope extraction to the primary meeting"

    # Must instruct AI to ignore embedded committee minutes
    assert prompt_text.downcase.include?("embedded") || prompt_text.downcase.include?("subordinate") || prompt_text.downcase.include?("other committee"),
      "Prompt must warn about embedded minutes from other committees"
  end

  test "analyze_meeting_content includes temporal context for future meeting" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [ {
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        } ]
      }
    end

    meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 3.days.from_now,
      detail_page_url: "https://example.com/meeting/future"
    )

    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      @service.send(:analyze_meeting_content, "Agenda text", "kb context", "packet", source: meeting)
    end

    prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

    assert prompt_text.include?("preview"), "Prompt must include 'preview' framing for future meeting"
    assert prompt_text.include?(meeting.starts_at.to_date.to_s), "Prompt must include meeting date"
    assert prompt_text.include?(Date.current.to_s), "Prompt must include today's date"
    assert prompt_text.include?("HAS NOT OCCURRED"), "Prompt must include preview instructions"
  end

  test "analyze_meeting_content includes recap framing for past meeting with minutes" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [ {
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        } ]
      }
    end

    meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 3.days.ago,
      detail_page_url: "https://example.com/meeting/past"
    )

    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      @service.send(:analyze_meeting_content, "Minutes text", "kb context", "minutes", source: meeting)
    end

    prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

    assert prompt_text.include?("recap"), "Prompt must include 'recap' framing for past meeting with minutes"
  end

  test "analyze_meeting_content uses preview framing for same-day future meeting" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [ {
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        } ]
      }
    end

    # Same calendar date as today, but hours in the future.
    meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 4.hours.from_now,
      detail_page_url: "https://example.com/meeting/today"
    )

    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      @service.send(:analyze_meeting_content, "Agenda text", "kb context", "packet", source: meeting)
    end

    prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

    # The interpolated framing line appears as "<framing> is one of: ...".
    # Use a line-anchored regex so "preview" doesn't falsely match within "stale_preview".
    assert_match(/^preview is one of:/, prompt_text,
      "Same-day future meeting should receive 'preview' framing, not 'stale_preview'")
  end

  test "analyze_meeting_content includes stale_preview framing for past meeting with only packet" do
    captured_params = nil

    mock_chat = lambda do |parameters:|
      captured_params = parameters
      {
        "choices" => [ {
          "message" => {
            "content" => {
              "headline" => "Test headline",
              "highlights" => [],
              "public_input" => [],
              "item_details" => []
            }.to_json
          }
        } ]
      }
    end

    meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 3.days.ago,
      detail_page_url: "https://example.com/meeting/stale"
    )

    @service.instance_variable_get(:@client).stub :chat, mock_chat do
      @service.send(:analyze_meeting_content, "Packet text", "kb context", "packet", source: meeting)
    end

    prompt_text = captured_params[:messages].map { |m| m[:content] }.join(" ")

    assert prompt_text.include?("stale_preview"), "Prompt must include 'stale_preview' framing for past meeting with only packet"
  end
end
