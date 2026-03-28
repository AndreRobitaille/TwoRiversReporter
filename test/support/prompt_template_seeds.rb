# Test helper that seeds all prompt templates into the test database.
# Used by tests that exercise OpenAiService methods.

require_relative "../../lib/prompt_template_data"

module PromptTemplateSeeds
  def self.create_all!
    PromptTemplateData::METADATA.each do |meta|
      key = meta[:key]
      next if PromptTemplate.exists?(key: key)

      prompt_data = PromptTemplateData::PROMPTS[key]
      raise "No prompt data for key '#{key}'" unless prompt_data

      PromptTemplate.create!(
        key: key,
        name: meta[:name],
        description: meta[:description],
        model_tier: meta[:model_tier],
        placeholders: meta[:placeholders],
        system_role: prompt_data[:system_role],
        instructions: prompt_data[:instructions]
      )
    end
  end
end
