require "test_helper"
require "minitest/mock"

class Ai::ExtractCommitteeMembersTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "extract_committee_members sends request and returns content" do
    minutes_text = <<~TEXT
      ROLL CALL
      Present: Smith, Johnson, Williams
      Absent: Davis
      Also Present: City Manager, Kyle Kordell
    TEXT

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => {
            "voting_members_present" => [ "Smith", "Johnson", "Williams" ],
            "voting_members_absent" => [ "Davis" ],
            "non_voting_staff" => [ { "name" => "Kyle Kordell", "capacity" => "City Manager" } ],
            "guests" => []
          }.to_json
        }
      } ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |parameters:|
      parameters[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
        !parameters.key?(:temperature) &&
        parameters[:response_format] == { type: "json_object" }
    end

    @service.instance_variable_set(:@client, mock_client)

    result = @service.extract_committee_members(minutes_text)
    parsed = JSON.parse(result)

    assert_equal [ "Smith", "Johnson", "Williams" ], parsed["voting_members_present"]
    assert_equal [ "Davis" ], parsed["voting_members_absent"]
    assert_equal 1, parsed["non_voting_staff"].size
    assert_equal "Kyle Kordell", parsed["non_voting_staff"][0]["name"]
    mock_client.verify
  end

  test "extract_committee_members truncates long text" do
    long_text = "x" * 60_000

    captured_params = nil
    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => '{"voting_members_present":[],"voting_members_absent":[],"non_voting_staff":[],"guests":[]}'
        }
      } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) { captured_params = parameters; mock_response } do
      @service.extract_committee_members(long_text)
    end

    user_msg = captured_params[:messages].find { |m| m[:role] == "user" }[:content]
    assert user_msg.length < 55_000, "Prompt should truncate long text"
  end

  test "extract_committee_members prompt includes json keyword" do
    captured_params = nil
    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => '{"voting_members_present":[],"voting_members_absent":[],"non_voting_staff":[],"guests":[]}'
        }
      } ]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) { captured_params = parameters; mock_response } do
      @service.extract_committee_members("ROLL CALL\nPresent: Smith")
    end

    all_text = captured_params[:messages].map { |m| m[:content] }.join(" ")
    assert_match(/json/i, all_text, "Prompt must contain 'json' for response_format")
  end
end
