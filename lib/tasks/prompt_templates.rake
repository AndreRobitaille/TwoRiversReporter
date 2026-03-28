require_relative "../prompt_template_data"

namespace :prompt_templates do
  desc "Populate all 15 PromptTemplate rows with prompt text extracted from OpenAiService heredocs"
  task populate: :environment do
    updated = 0
    missing = []

    PromptTemplateData::PROMPTS.each do |key, data|
      template = PromptTemplate.find_by(key: key)
      if template.nil?
        missing << key
        next
      end

      attrs = { instructions: data[:instructions].strip }
      attrs[:system_role] = data[:system_role].present? ? data[:system_role].strip : nil

      template.editor_note = "Populated from OpenAiService heredoc"
      template.update!(**attrs)
      updated += 1
      puts "  Updated '#{key}'"
    end

    if missing.any?
      puts "\nMISSING (run db:seed first): #{missing.join(', ')}"
    end

    puts "\nDone. Updated #{updated}/#{PromptTemplateData::PROMPTS.size} prompt templates."
  end

  desc "Check that all required prompt templates exist and have real content"
  task validate: :environment do
    expected_keys = PromptTemplateData::PROMPTS.keys

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

    if missing.any?
      puts "MISSING templates (run db:seed): #{missing.join(', ')}"
    end

    if placeholder.any?
      puts "PLACEHOLDER text (populate via admin UI): #{placeholder.join(', ')}"
    end

    if missing.empty? && placeholder.empty?
      puts "All #{expected_keys.size} prompt templates present with real content."
    end
  end
end
