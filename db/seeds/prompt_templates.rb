require_relative "../../lib/prompt_template_data"

puts "Seeding prompt templates from PromptTemplateData..."

PromptTemplateData::METADATA.each do |meta|
  key = meta[:key]
  next if PromptTemplate.exists?(key: key)

  prompt_data = PromptTemplateData::PROMPTS.fetch(key)

  template = PromptTemplate.create!(
    key: key,
    name: meta[:name],
    description: meta[:description],
    usage_context: meta[:usage_context],
    model_tier: meta[:model_tier],
    placeholders: meta[:placeholders],
    system_role: prompt_data[:system_role],
    instructions: prompt_data[:instructions],
    editor_note: "Seeded from PromptTemplateData"
  )

  puts "  Created PromptTemplate '#{template.key}' (ID: #{template.id})"
end

puts "Done. #{PromptTemplate.count} prompt templates in database."
