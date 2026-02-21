require "test_helper"
require "minitest/mock"

class Ai::OpenAiServiceGenerateDescriptionTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "uses activity-based prompt when 3 or more agenda items" do
    topic_context = {
      topic_name: "Lakefront Development",
      agenda_items: [
        { title: "Lakefront proposal review", summary: "Council reviewed the proposal" },
        { title: "Lakefront environmental study", summary: "Environmental report presented" },
        { title: "Lakefront zoning change", summary: "Zoning amendment discussed" }
      ],
      headlines: [ "Council advances lakefront plan" ]
    }

    mock_response = {
      "choices" => [ { "message" => { "content" => "Tracks city plans for the lakefront area." } } ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |parameters:|
      messages = parameters[:messages]
      user_prompt = messages.find { |m| m[:role] == "user" }[:content]

      parameters[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
        user_prompt.include?("based on the following activity") &&
        user_prompt.include?("Lakefront Development") &&
        user_prompt.include?("Lakefront proposal review")
    end

    @service.instance_variable_set(:@client, mock_client)

    result = @service.generate_topic_description(topic_context)

    assert_equal "Tracks city plans for the lakefront area.", result
    mock_client.verify
  end

  test "uses concept-based prompt when fewer than 3 agenda items" do
    topic_context = {
      topic_name: "Senior Center Funding",
      agenda_items: [
        { title: "Senior center budget request", summary: "Funding discussed" }
      ],
      headlines: []
    }

    mock_response = {
      "choices" => [ { "message" => { "content" => "Funding and operations for the senior center." } } ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |parameters:|
      messages = parameters[:messages]
      user_prompt = messages.find { |m| m[:role] == "user" }[:content]

      parameters[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
        user_prompt.include?("broad civic-concept") &&
        user_prompt.include?("Senior Center Funding")
    end

    @service.instance_variable_set(:@client, mock_client)

    result = @service.generate_topic_description(topic_context)

    assert_equal "Funding and operations for the senior center.", result
    mock_client.verify
  end

  test "returns nil on empty API response" do
    topic_context = {
      topic_name: "Empty Topic",
      agenda_items: [],
      headlines: []
    }

    mock_response = {
      "choices" => [ { "message" => { "content" => "" } } ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |parameters:|
      true
    end

    @service.instance_variable_set(:@client, mock_client)

    result = @service.generate_topic_description(topic_context)

    assert_nil result
    mock_client.verify
  end

  test "returns nil when API response content is nil" do
    topic_context = {
      topic_name: "Nil Topic",
      agenda_items: [],
      headlines: []
    }

    mock_response = {
      "choices" => [ { "message" => { "content" => nil } } ]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |parameters:|
      true
    end

    @service.instance_variable_set(:@client, mock_client)

    result = @service.generate_topic_description(topic_context)

    assert_nil result
    mock_client.verify
  end
end
