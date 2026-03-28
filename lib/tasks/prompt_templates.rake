namespace :prompt_templates do
  desc "Check that all required prompt templates exist and have real content"
  task validate: :environment do
    expected_keys = %w[
      extract_votes extract_committee_members extract_topics
      refine_catchall_topic re_extract_item_topics triage_topics
      analyze_topic_summary render_topic_summary
      analyze_topic_briefing render_topic_briefing
      generate_briefing_interim generate_topic_description_detailed
      generate_topic_description_broad
      analyze_meeting_content render_meeting_summary
    ]

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
