namespace :topics do
  desc "Backfill knowledge source topics using heuristic matching"
  task backfill_knowledge_sources: :environment do
    puts "Starting knowledge source topic backfill..."

    Topic.find_each do |topic|
      puts "Checking topic: #{topic.name}"

      # Match sources by title or verification notes containing topic name
      # This is a basic heuristic
      query = "%#{topic.name}%"
      matches = KnowledgeSource.where("title ILIKE ? OR verification_notes ILIKE ?", query, query)

      matches.find_each do |source|
        unless source.topics.exists?(topic.id)
          puts "  -> Linking source: #{source.title}"
          KnowledgeSourceTopic.create!(
            knowledge_source: source,
            topic: topic,
            relevance_score: 0.5, # Default medium score
            verified: false # Requires review
          )
        end
      end
    end

    puts "Backfill complete."
  end
end
