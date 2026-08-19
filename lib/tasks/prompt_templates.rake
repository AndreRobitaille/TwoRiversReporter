require_relative "../prompt_template_data"
require Rails.root.join("app/services/ai/open_ai_service")
require "digest"

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

  desc "Plan or safely apply selected PromptTemplateData changes (KEYS=a,b APPLY=true EXPECTED_SHA256S=a=sha,b=sha)"
  task sync_selected: :environment do
    keys = ENV.fetch("KEYS", "").split(",").reject(&:blank?)
    apply = ENV["APPLY"] == "true"
    expected = ENV.fetch("EXPECTED_SHA256S", "").split(",").filter_map do |pair|
      key, fingerprint = pair.split("=", 2)
      [ key, fingerprint ] if key.present? && fingerprint.present?
    end.to_h
    abort "KEYS must name at least one prompt template" if keys.empty?

    unknown = keys - PromptTemplateData::PROMPTS.keys
    abort "Unknown prompt template keys: #{unknown.join(', ')}" if unknown.any?

    canonical = ->(system_role:, instructions:, model_tier:) do
      Digest::SHA256.hexdigest(JSON.generate({
        system_role: system_role.presence,
        instructions: instructions.to_s.strip,
        model_tier: model_tier
      }))
    end

    changes = keys.map do |key|
      meta = PromptTemplateData::METADATA.find { |entry| entry[:key] == key }
      data = PromptTemplateData::PROMPTS.fetch(key)
      template = PromptTemplate.find_by(key: key)
      target = {
        system_role: data[:system_role].presence&.strip,
        instructions: data.fetch(:instructions).strip,
        model_tier: meta.fetch(:model_tier)
      }
      current_fingerprint = if template
        canonical.call(
          system_role: template.system_role,
          instructions: template.instructions,
          model_tier: template.model_tier
        )
      end
      target_fingerprint = canonical.call(**target)

      puts "#{key}: current=#{current_fingerprint || 'missing'} target=#{target_fingerprint} #{current_fingerprint == target_fingerprint ? 'unchanged' : 'change'}"
      [ key, template, meta, target, current_fingerprint ]
    end

    unless apply
      puts "Dry run only. Re-run with APPLY=true and EXPECTED_SHA256S for every existing changed row."
      next
    end

    changes.each do |key, template, _meta, _target, current_fingerprint|
      next unless template && expected[key] != current_fingerprint

      abort "Fingerprint mismatch for #{key}: expected #{expected[key] || 'missing'}, found #{current_fingerprint}"
    end

    PromptTemplate.transaction do
      changes.each do |key, template, meta, target, _current_fingerprint|
        template ||= PromptTemplate.new(key: key)
        template.editor_note = "Explicit GPT-5.6 migration sync from PromptTemplateData"
        template.update!(
          name: meta.fetch(:name),
          description: meta.fetch(:description),
          usage_context: meta[:usage_context],
          placeholders: meta[:placeholders],
          **target
        )
        puts "Applied #{key}"
      end
    end
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
