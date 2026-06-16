# Test helper that seeds all prompt templates into the test database.
# Used by tests that exercise OpenAiService methods.

require_relative "../../lib/prompt_template_data"

module PromptTemplateSeeds
  def self.create_all!
    PromptTemplateData::METADATA.each do |meta|
      key = meta[:key]
      prompt_data = PromptTemplateData::PROMPTS[key]
      raise "No prompt data for key '#{key}'" unless prompt_data

      template = PromptTemplate.find_or_initialize_by(key: key)
      attrs = {
        name: meta[:name],
        description: meta[:description],
        usage_context: meta[:usage_context],
        model_tier: meta[:model_tier],
        placeholders: meta[:placeholders],
        system_role: prompt_data[:system_role],
        instructions: prompt_data[:instructions]
      }

      next if template.persisted? && attrs.all? { |attr, value| template.public_send(attr) == value }

      template.update!(attrs)
    end
  end
end
