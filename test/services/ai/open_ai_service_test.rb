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
