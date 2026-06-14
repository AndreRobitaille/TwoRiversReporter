require "test_helper"

class Ai::OpenAiServiceExtractKnowledgeTest < ActiveSupport::TestCase
  test "extract_knowledge returns JSON content" do
    PromptTemplate.find_or_create_by!(key: "extract_knowledge") do |t|
      t.name = "Knowledge Extraction"
      t.model_tier = "default"
      t.system_role = "You extract civic knowledge."
      t.instructions = "Extract facts from: {{summary_json}}\n\nRaw text: {{raw_text}}\n\nExisting KB: {{existing_kb}}\n\nReturn json."
    end

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => '{"entries":[{"title":"Test fact","confidence":0.9}]}'
        }
      } ]
    }

    mock_chat = lambda do |parameters:|
      mock_response
    end

    service = Ai::OpenAiService.new
    result = nil
    service.instance_variable_get(:@client).stub :chat, mock_chat do
      result = service.extract_knowledge(
        summary_json: '{"headline":"Test"}',
        raw_text: "Meeting text",
        existing_kb: "No entries.",
        source: nil
      )
    end

    assert_equal '{"entries":[{"title":"Test fact","confidence":0.9}]}', result
  end
end

class Ai::OpenAiServiceTriageKnowledgeTest < ActiveSupport::TestCase
  test "triage_knowledge returns JSON content" do
    PromptTemplate.find_or_create_by!(key: "triage_knowledge") do |t|
      t.name = "Knowledge Triage"
      t.model_tier = "default"
      t.system_role = "You triage knowledge."
      t.instructions = "Triage: {{entries_json}}\n\nExisting: {{existing_kb}}\n\nReturn json."
    end

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => '{"decisions":[{"knowledge_source_id":1,"action":"approve"}]}'
        }
      } ]
    }

    mock_chat = lambda do |parameters:|
      mock_response
    end

    service = Ai::OpenAiService.new
    result = nil
    service.instance_variable_get(:@client).stub :chat, mock_chat do
      result = service.triage_knowledge(
        entries_json: '[{"id":1,"title":"Test"}]',
        existing_kb: "No entries.",
        source: nil
      )
    end

    assert_equal '{"decisions":[{"knowledge_source_id":1,"action":"approve"}]}', result
  end
end

class Ai::OpenAiServiceExtractKnowledgePatternsTest < ActiveSupport::TestCase
  test "extract_knowledge_patterns returns JSON content" do
    PromptTemplate.find_or_create_by!(key: "extract_knowledge_patterns") do |t|
      t.name = "Knowledge Pattern Detection"
      t.model_tier = "default"
      t.system_role = "You detect patterns."
      t.instructions = "Entries: {{knowledge_entries}}\n\nSummaries: {{recent_summaries}}\n\nTopics: {{topic_metadata}}\n\nReturn json."
    end

    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => '{"entries":[{"title":"Recurring recusal","confidence":0.85}]}'
        }
      } ]
    }

    mock_chat = lambda do |parameters:|
      mock_response
    end

    service = Ai::OpenAiService.new
    result = nil
    service.instance_variable_get(:@client).stub :chat, mock_chat do
      result = service.extract_knowledge_patterns(
        knowledge_entries: "Entry 1...",
        recent_summaries: "Summary...",
        topic_metadata: "Topic data...",
        source: nil
      )
    end

    assert_equal '{"entries":[{"title":"Recurring recusal","confidence":0.85}]}', result
  end
end

class Ai::OpenAiServiceGeneratedImageBriefTest < ActiveSupport::TestCase
  test "build_generated_image_brief returns parsed json" do
    PromptTemplate.find_or_create_by!(key: "generated_image_brief") do |t|
      t.name = "Generated Image Brief"
      t.model_tier = "lightweight"
      t.system_role = "You are a civic image brief writer. Return only valid JSON."
      t.instructions = "Create a concise JSON brief for generating a civic image. Inputs: {{imageable_type}} {{composite}} {{source_text}}"
    end

    long_text = "x" * 13_000
    mock_response = {
      "choices" => [ {
        "message" => {
          "content" => '{"civic_issue":"Traffic","composition":"Street scene","avoid":["logos"]}'
        }
      } ]
    }

    mock_chat = lambda do |parameters:|
      assert_equal Ai::OpenAiService::LIGHTWEIGHT_MODEL, parameters[:model]
      assert_equal({ type: "json_object" }, parameters[:response_format])
      assert_operator parameters[:messages].last[:content].length, :<, long_text.length
      mock_response
    end

    service = Ai::OpenAiService.new
    result = nil
    assert_difference -> { PromptRun.where(prompt_template_key: "generated_image_brief").count }, 1 do
    service.instance_variable_get(:@client).stub :chat, mock_chat do
      result = service.build_generated_image_brief(
        imageable_type: "Meeting",
        source_text: long_text,
        composite: { "theme" => "public" }
      )
    end
    end

    assert_equal({ "civic_issue" => "Traffic", "composition" => "Street scene", "avoid" => [ "logos" ] }, result)
    assert_equal "Meeting", PromptRun.last.placeholder_values["imageable_type"]
    assert_operator PromptRun.last.placeholder_values["source_text"].length, :<, long_text.length
  end

  test "build_generated_image_brief raises on malformed json" do
    PromptTemplate.find_or_create_by!(key: "generated_image_brief") do |t|
      t.name = "Generated Image Brief"
      t.model_tier = "lightweight"
      t.system_role = "You are a civic image brief writer. Return only valid JSON."
      t.instructions = "Create a concise JSON brief for generating a civic image. Inputs: {{imageable_type}} {{composite}} {{source_text}}"
    end

    service = Ai::OpenAiService.new
    before_count = PromptRun.where(prompt_template_key: "generated_image_brief").count
    service.instance_variable_get(:@client).stub :chat, ->(**) { { "choices" => [ { "message" => { "content" => "not json" } } ] } } do
      error = assert_raises(RuntimeError) do
        service.build_generated_image_brief(imageable_type: "Meeting", source_text: "Text", composite: {})
      end

      assert_match(/generated image brief invalid JSON/, error.message)
    end
    assert_equal before_count + 1, PromptRun.where(prompt_template_key: "generated_image_brief").count
    assert_equal "not json", PromptRun.where(prompt_template_key: "generated_image_brief").last.response_body
  end

  test "build_generated_image_brief raises on missing keys" do
    PromptTemplate.find_or_create_by!(key: "generated_image_brief") do |t|
      t.name = "Generated Image Brief"
      t.model_tier = "lightweight"
      t.system_role = "You are a civic image brief writer. Return only valid JSON."
      t.instructions = "Create a concise JSON brief for generating a civic image. Inputs: {{imageable_type}} {{composite}} {{source_text}}"
    end

    service = Ai::OpenAiService.new
    before_count = PromptRun.where(prompt_template_key: "generated_image_brief").count
    service.instance_variable_get(:@client).stub :chat, ->(**) { { "choices" => [ { "message" => { "content" => '{"civic_issue":"Traffic"}' } } ] } } do
      error = assert_raises(RuntimeError) do
        service.build_generated_image_brief(imageable_type: "Meeting", source_text: "Text", composite: {})
      end

      assert_match(/missing required keys/, error.message)
    end
    assert_equal before_count + 1, PromptRun.where(prompt_template_key: "generated_image_brief").count
    assert_equal '{"civic_issue":"Traffic"}', PromptRun.where(prompt_template_key: "generated_image_brief").last.response_body
  end
end

class Ai::OpenAiServiceGenerateCivicImageTest < ActiveSupport::TestCase
  test "generate_civic_image omits response_format for gpt-image models" do
    image_client = Struct.new(:captured_parameters) do
      def generate(parameters:)
        self.captured_parameters = parameters
        {
          "data" => [
            {
              "b64_json" => Base64.strict_encode64("jpeg-bytes")
            }
          ]
        }
      end
    end.new

    service = Ai::OpenAiService.new
    result = nil

    original_model = Ai::OpenAiService::IMAGE_MODEL
    Ai::OpenAiService.send(:remove_const, :IMAGE_MODEL)
    Ai::OpenAiService.const_set(:IMAGE_MODEL, "gpt-image-1")

    service.instance_variable_get(:@client).stub :images, image_client do
      result = service.generate_civic_image(prompt: "Create a civic illustration")
    end

    assert_equal "jpeg-bytes", result[:bytes]
    assert_equal "gpt-image-1", result[:model]
    assert_equal "1536x1024", result[:size]
    assert_equal "jpeg", result[:format]
    assert_equal "gpt-image-1", image_client.captured_parameters[:model]
    assert_equal "Create a civic illustration", image_client.captured_parameters[:prompt]
    assert_equal "1536x1024", image_client.captured_parameters[:size]
    assert_nil image_client.captured_parameters[:response_format]
    assert_nil image_client.captured_parameters[:format]
    assert_nil image_client.captured_parameters[:output_format]
  ensure
    Ai::OpenAiService.send(:remove_const, :IMAGE_MODEL)
    Ai::OpenAiService.const_set(:IMAGE_MODEL, original_model)
  end

  test "generate_civic_image decodes base64 image bytes" do
    image_client = Struct.new(:captured_parameters) do
      def generate(parameters:)
        self.captured_parameters = parameters
        {
          "data" => [
            {
              "b64_json" => Base64.strict_encode64("jpeg-bytes"),
              "revised_prompt" => "revised prompt"
            }
          ]
        }
      end
    end.new

    service = Ai::OpenAiService.new
    result = nil
    service.instance_variable_get(:@client).stub :images, image_client do
      result = service.generate_civic_image(prompt: "Create a civic illustration")
    end

    assert_equal "jpeg-bytes", result[:bytes]
    assert_equal "revised prompt", result[:revised_prompt]
    assert_equal Ai::OpenAiService::IMAGE_MODEL, result[:model]
    assert_equal "1536x1024", result[:size]
    assert_equal "jpeg", result[:format]
    assert_equal Ai::OpenAiService::IMAGE_MODEL, image_client.captured_parameters[:model]
    assert_equal "Create a civic illustration", image_client.captured_parameters[:prompt]
    assert_equal "1536x1024", image_client.captured_parameters[:size]
    assert_nil image_client.captured_parameters[:response_format]
    assert_nil image_client.captured_parameters[:format]
    assert_nil image_client.captured_parameters[:output_format]
  end

  test "generate_civic_image raises when b64 is missing" do
    image_client = Struct.new(:captured_parameters) do
      def generate(parameters:)
        self.captured_parameters = parameters
        { "data" => [ {} ] }
      end
    end.new

    service = Ai::OpenAiService.new
    service.instance_variable_get(:@client).stub :images, image_client do
      error = assert_raises(RuntimeError) do
        service.generate_civic_image(prompt: "Create a civic illustration")
      end

      assert_match(/empty b64_json/, error.message)
    end
  end
end
