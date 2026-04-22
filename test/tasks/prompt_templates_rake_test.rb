require "test_helper"
require "rake"

class PromptTemplatesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("prompt_templates:populate")
    Rake::Task["prompt_templates:populate"].reenable
  end

  test "populate refreshes existing placeholders metadata" do
    template = PromptTemplate.create!(
      key: "extract_votes",
      name: "Vote Extraction",
      description: "Extracts motions and vote records from meeting minutes",
      model_tier: "default",
      placeholders: [ { "name" => "stale", "description" => "stale" } ],
      system_role: "Old role",
      instructions: "Old instructions"
    )

    Rake::Task["prompt_templates:populate"].invoke

    assert_equal PromptTemplateData::METADATA.find { |meta| meta[:key] == template.key }[:placeholders], template.reload.placeholders
  ensure
    Rake::Task["prompt_templates:populate"].reenable
  end
end
