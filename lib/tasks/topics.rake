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

  desc "Generate descriptions for approved topics missing them"
  task generate_descriptions: :environment do
    scope = Topic.approved.where(description: [ nil, "" ])
    total = scope.count
    puts "Generating descriptions for #{total} approved topics..."

    scope.find_each.with_index(1) do |topic, i|
      print "[#{i}/#{total}] #{topic.name}... "
      Topics::GenerateDescriptionJob.perform_now(topic.id)
      topic.reload
      if topic.description.present?
        puts topic.description
      else
        puts "(no description generated)"
      end
    end

    puts "Done. #{Topic.approved.where.not(description: [ nil, "" ]).count} topics now have descriptions."
  end

  desc "Re-extract items from a broad topic into specific topics"
  task :split_broad_topic, [ :topic_name ] => :environment do |_t, args|
    topic_name = args[:topic_name]
    abort "Usage: bin/rails topics:split_broad_topic[topic_name]" if topic_name.blank?

    normalized = Topic.normalize_name(topic_name)
    topic = Topic.find_by("LOWER(name) = ?", normalized)
    abort "Topic '#{topic_name}' not found" unless topic

    links = AgendaItemTopic.where(topic: topic).includes(agenda_item: { meeting: {}, meeting_documents: {} })
    puts "Found #{links.count} agenda items linked to '#{topic.name}'"
    abort "No items to re-extract" if links.empty?

    ai_service = Ai::OpenAiService.new
    existing_topics = Topic.reusable.where.not(id: topic.id).pluck(:name)

    removed = 0
    retagged = 0
    skipped = 0
    split_topic_cache = {}

    links.find_each do |link|
      item = link.agenda_item
      meeting = item.meeting

      # Gather document context
      doc_parts = []
      item.meeting_documents.each do |doc|
        next if doc.extracted_text.blank?
        doc_parts << doc.extracted_text.truncate(2000, separator: " ")
      end
      meeting.meeting_documents.where(document_type: %w[packet_pdf minutes_pdf]).each do |doc|
        next if doc.extracted_text.blank?
        doc_parts << doc.extracted_text.truncate(4000, separator: " ")
      end
      doc_text = doc_parts.join("\n---\n")

      print "[#{meeting.starts_at&.strftime('%Y-%m-%d')} #{meeting.body_name}] #{item.title.truncate(60)}... "

      begin
        result = ai_service.re_extract_item_topics(
          item_title: item.title,
          item_summary: item.summary,
          document_text: doc_text,
          broad_topic_name: topic.name,
          existing_topics: existing_topics
        )

        data = JSON.parse(result)
        tags = data["tags"] || []
        topic_worthy = data.fetch("topic_worthy", false)
        routing_context = {
          item_title: item.title,
          item_summary: item.summary,
          meeting_body_name: meeting.body_name,
          document_text: doc_text,
          existing_topics: existing_topics
        }

        if !topic_worthy || tags.empty?
          link.destroy!
          removed += 1
          puts "NOT TOPIC-WORTHY (removed)"
        else
          tags.each do |new_name|
            normalized_new_name = Topic.normalize_name(new_name)
            new_topic = split_topic_cache[normalized_new_name]
            unless new_topic
              new_topic = Topic.where("LOWER(name) = ?", normalized_new_name).where.not(status: "blocked").first
              new_topic ||= Topics::FindOrCreateService.call(new_name, **routing_context)
              split_topic_cache[normalized_new_name] = new_topic if new_topic
            end
            if new_topic
              AgendaItemTopic.find_or_create_by!(agenda_item: item, topic: new_topic)
              puts "-> #{new_topic.name}"
              existing_topics << new_topic.name unless existing_topics.include?(new_topic.name)
            else
              puts "-> #{new_name} (BLOCKED)"
            end
          end
          link.destroy!
          retagged += 1
        end
      rescue JSON::ParserError, Faraday::Error => e
        puts "ERROR: #{e.class} #{e.message}"
        skipped += 1
      end
    end

    puts "\nDone. Removed: #{removed}, Retagged: #{retagged}, Errors: #{skipped}"
    remaining = AgendaItemTopic.where(topic: topic).count
    puts "#{remaining} items still linked to '#{topic.name}'"
  end

  desc "Add process-category names to topic blocklist (idempotent)"
  task seed_category_blocklist: :environment do
    categories = [
      "zoning",
      "infrastructure",
      "public safety",
      "parks & rec",
      "finance",
      "licensing",
      "personnel",
      "governance"
    ]

    categories.each do |name|
      normalized = name.to_s.strip.downcase.gsub(/[[:punct:]]/, "").squish
      entry = TopicBlocklist.find_or_initialize_by(name: normalized)
      if entry.new_record?
        entry.reason = "Process category — too broad for a topic"
        entry.save!
        puts "Added to blocklist: #{name}"
      else
        puts "Already blocked: #{name}"
      end
    end
  end

  desc "Mark umbrella topics unsafe for auto-reuse"
  task mark_unsafe_for_reuse: :environment do
    names = ENV["TOPICS"].to_s.split(",").map { |name| Topic.normalize_name(name) }.reject(&:blank?)
    abort "Usage: TOPICS='redevelopment,community visioning' bin/rails topics:mark_unsafe_for_reuse" if names.empty?

    topics = Topic.where(name: names)
    topics.update_all(reuse_strategy: "unsafe_for_auto_reuse")

    puts "Marked topics: #{topics.pluck(:name).join(", ")}"
  end
end
