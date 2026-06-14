require "test_helper"
require "rake"

class PromptTemplatesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("prompt_templates:populate")
    Rake::Task["prompt_templates:populate"].reenable
  end

  test "populate refreshes existing placeholders metadata" do
    template = PromptTemplate.find_or_create_by!(key: "extract_votes") do |t|
      t.name = "Vote Extraction"
      t.description = "Extracts motions and vote records from meeting minutes"
      t.model_tier = "default"
      t.placeholders = [ { "name" => "stale", "description" => "stale" } ]
      t.system_role = "Old role"
      t.instructions = "Old instructions"
    end

    template.update!(placeholders: [ { "name" => "stale", "description" => "stale" } ])

    Rake::Task["prompt_templates:populate"].invoke

    assert_equal PromptTemplateData::METADATA.find { |meta| meta[:key] == "extract_votes" }[:placeholders], template.reload.placeholders
  ensure
    Rake::Task["prompt_templates:populate"].reenable
  end

  test "populate creates missing templates from PromptTemplateData" do
    PromptTemplate.where(key: "generated_image_brief").destroy_all

    assert_difference -> { PromptTemplate.where(key: "generated_image_brief").count }, 1 do
      Rake::Task["prompt_templates:populate"].invoke
    end

    template = PromptTemplate.find_by!(key: "generated_image_brief")
    assert_equal "Generated Image Brief", template.name
    assert_equal PromptTemplateData::PROMPTS["generated_image_brief"][:instructions].strip, template.instructions
  ensure
    Rake::Task["prompt_templates:populate"].reenable
  end

  test "validate exits nonzero when templates are missing" do
    PromptTemplate.where(key: "generated_image_brief").destroy_all

    out, err = capture_io do
      assert_raises(SystemExit) do
        Rake::Task["prompt_templates:validate"].invoke
      end
    end

    assert_match(/MISSING templates/, out + err)
  ensure
    Rake::Task["prompt_templates:validate"].reenable
  end

  test "validate is driven by Ai::OpenAiService required prompt keys" do
    rake_source = File.read(Rails.root.join("lib/tasks/prompt_templates.rake"))
    assert_includes rake_source, "Ai::OpenAiService::REQUIRED_PROMPT_KEYS"
  end
end
