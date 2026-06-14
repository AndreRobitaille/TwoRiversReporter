require_relative "../prompt_template_data"
require Rails.root.join("app/services/ai/open_ai_service")

namespace :prompt_templates do
  REQUIRED_TEMPLATE_KEYS = Ai::OpenAiService::REQUIRED_PROMPT_KEYS.freeze

  desc "Populate all PromptTemplate rows with prompt text from PromptTemplateData"
  task populate: :environment do
    updated = 0
    missing = []

    PromptTemplateData::METADATA.each do |meta|
      key = meta[:key]
      data = PromptTemplateData::PROMPTS[key]
      template = PromptTemplate.find_or_initialize_by(key: key)

      attrs = {
        key: key,
        name: meta[:name],
        description: meta[:description],
        usage_context: meta[:usage_context],
        model_tier: meta[:model_tier],
        instructions: data[:instructions].strip,
        placeholders: meta&.fetch(:placeholders)
      }
      attrs[:system_role] = data[:system_role].present? ? data[:system_role].strip : nil

      template.editor_note = template.persisted? ? "Populated from PromptTemplateData" : "Created from PromptTemplateData"
      template.update!(**attrs)
      updated += 1
      action = template.previously_new_record? ? "Created" : "Updated"
      puts "  #{action} '#{key}'"
    end

    puts "\nDone. Synced #{updated}/#{PromptTemplateData::METADATA.size} prompt templates."
  end

  desc "Check that all required prompt templates exist and have real content"
  task validate: :environment do
    expected_keys = REQUIRED_TEMPLATE_KEYS
    missing_in_data = expected_keys - PromptTemplateData::PROMPTS.keys
    missing_in_metadata = expected_keys - PromptTemplateData::METADATA.map { |meta| meta[:key] }

    missing = []
    placeholder = []

    expected_keys.each do |key|
      template = PromptTemplate.find_by(key: key)
      if template.nil?
        missing << key
      elsif template.instructions.include?("TODO")
        placeholder << key
      end
    end

    if missing_in_data.any?
      puts "MISSING from PromptTemplateData: #{missing_in_data.join(', ')}"
    end

    if missing_in_metadata.any?
      puts "MISSING from PromptTemplateData metadata: #{missing_in_metadata.join(', ')}"
    end

    if missing.any?
      puts "MISSING templates (run prompt_templates:populate): #{missing.join(', ')}"
    end

    if placeholder.any?
      puts "PLACEHOLDER text (populate via admin UI): #{placeholder.join(', ')}"
    end

    if missing.empty? && placeholder.empty? && missing_in_data.empty? && missing_in_metadata.empty?
      puts "All #{expected_keys.size} prompt templates present with real content."
      exit 0
    else
      exit 1
    end
  end
end
