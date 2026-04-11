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
    existing_topics = Topic.approved.where.not(id: topic.id).pluck(:name)

    removed = 0
    retagged = 0
    skipped = 0

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

        if !topic_worthy || tags.empty?
          link.destroy!
          removed += 1
          puts "NOT TOPIC-WORTHY (removed)"
        else
          tags.each do |new_name|
            new_topic = Topics::FindOrCreateService.call(new_name)
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

  desc "One-time backfill: detach hollow topic appearances from standing-slot agenda items"
  task prune_hollow_appearances: :environment do
    dry_run = ENV["DRY_RUN"].present?
    confirmed = ENV["CONFIRM"].present?

    unless dry_run || confirmed
      puts "Refusing to run without DRY_RUN=1 or CONFIRM=1."
      puts "  Preview:   DRY_RUN=1 bin/rails topics:prune_hollow_appearances"
      puts "  Execute:   CONFIRM=1 bin/rails topics:prune_hollow_appearances"
      exit 1
    end

    standing_patterns = [
      "updates and action",
      "director update",
      "director's report",
      "directors report",
      "administrator's report",
      "administrators report",
      "chief's report",
      "chiefs report",
      "any other items",
      "any other matters",
      "council communications",
      "communications",
      "citizens' comments",
      "open forum"
    ].freeze

    motion_keywords = %w[
      motion seconded carried adopted approved approve
      ayes nays resolution ordinance
      voted vote unanimously rejected denied defeated
      tabled referred recommend recommended
    ].freeze

    normalize = ->(title) {
      title.to_s
        .gsub(/\A\s*\d+[a-z]?\.?\s*/i, "")
        .gsub(/\s*,?\s*as needed\s*\z/i, "")
        .gsub(/\s*,?\s*if applicable\s*\z/i, "")
        .gsub(/\s+/, " ")
        .downcase
        .strip
    }

    matches_pattern = ->(title) {
      standing_patterns.any? { |pat| title.include?(pat) }
    }

    puts "[#{dry_run ? 'DRY RUN' : 'LIVE'}] Scanning AgendaItemTopic rows for hollow appearances..."

    # Pre-compute normalized-title frequency per topic for auto-detection
    title_counts_by_topic = Hash.new { |h, k| h[k] = Hash.new(0) }
    AgendaItemTopic.includes(:agenda_item).find_each do |ait|
      next unless ait.agenda_item
      norm = normalize.call(ait.agenda_item.title)
      title_counts_by_topic[ait.topic_id][norm] += 1
    end

    # PASS 1: collect planned prunes. No destructive writes in this loop.
    planned = []

    AgendaItemTopic.includes(agenda_item: :meeting).find_each do |ait|
      item = ait.agenda_item
      next unless item

      norm = normalize.call(item.title)
      repeats = title_counts_by_topic[ait.topic_id][norm] >= 3
      candidate = matches_pattern.call(norm) || repeats
      next unless candidate

      next if Motion.where(agenda_item_id: item.id).exists?

      meeting = item.meeting
      next unless meeting

      summary = meeting.meeting_summaries.order(created_at: :desc).first
      entry = nil
      if summary&.generation_data.is_a?(Hash)
        details = summary.generation_data["item_details"]
        if details.is_a?(Array)
          entry = details.find do |e|
            next false unless e.is_a?(Hash)
            e_title = e["agenda_item_title"]
            e_title.is_a?(String) && normalize.call(e_title) == norm
          end
        end
      end

      if entry
        next unless entry["vote"].nil? && entry["decision"].nil? && entry["public_hearing"].nil?

        summary_text = entry["summary"].to_s
        next unless summary_text.length < 600
        lowered = summary_text.downcase
        next if motion_keywords.any? { |kw| lowered.include?(kw) } || lowered.include?("public hearing")
      end

      planned << {
        agenda_item_topic_id: ait.id,
        topic_id: ait.topic_id,
        agenda_item_id: item.id,
        meeting_id: meeting.id,
        title: item.title
      }
      puts "  PRUNE: topic=#{ait.topic_id} meeting=#{meeting.id} item=\"#{item.title}\""
    end

    # Per-topic aggregate preview — gives the operator a "what will actually
    # happen to each topic" view before any destructive action.
    planned_by_topic = planned.group_by { |p| p[:topic_id] }
    puts "\n=== Per-Topic Summary ==="
    planned_by_topic.each do |topic_id, rows|
      topic = Topic.find_by(id: topic_id)
      next unless topic
      total = topic.topic_appearances.count
      to_prune = rows.size
      remaining = total - to_prune
      outcome = case remaining
      when 0 then "BLOCK"
      when 1 then "DORMANT"
      else "REBRIEF (#{remaining} remain)"
      end
      puts "  topic=#{topic_id} \"#{topic.name}\" — #{total} total, #{to_prune} prune, outcome=#{outcome}"
    end
    puts "Total: #{planned.size} appearances across #{planned_by_topic.size} topics."

    if dry_run
      puts "\nDRY RUN — no changes made."
      next
    end

    # LIVE: write snapshot before any destroys, so rollback is possible.
    snapshot_dir = Rails.root.join("tmp")
    FileUtils.mkdir_p(snapshot_dir)
    snapshot_path = snapshot_dir.join("hollow_prune_snapshot_#{Time.current.strftime('%Y%m%d_%H%M%S')}.json")
    snapshot = {
      created_at: Time.current.iso8601,
      appearances: planned,
      affected_topics: planned_by_topic.keys.map do |topic_id|
        t = Topic.find_by(id: topic_id)
        next nil unless t
        {
          topic_id: t.id,
          name: t.name,
          status_before: t.status,
          lifecycle_status_before: t.lifecycle_status,
          resident_impact_score_before: t.resident_impact_score
        }
      end.compact
    }
    File.write(snapshot_path, JSON.pretty_generate(snapshot))
    puts "\nSnapshot written: #{snapshot_path}"
    puts "  (Keep this file for rollback. To manually recreate, re-run ExtractTopicsJob for affected meetings.)"

    # Execute destroys inside one transaction per AgendaItemTopic.
    planned.each do |row|
      ActiveRecord::Base.transaction do
        ait = AgendaItemTopic.find_by(id: row[:agenda_item_topic_id])
        next unless ait
        ait.destroy!
        TopicAppearance.where(topic_id: row[:topic_id], agenda_item_id: row[:agenda_item_id]).destroy_all
      end
    end

    puts "\nPruned #{planned.size} appearances."

    # Apply demotion rules per affected topic.
    planned_by_topic.each_key do |topic_id|
      topic = Topic.find_by(id: topic_id)
      next unless topic

      remaining = topic.topic_appearances.count
      case remaining
      when 0
        topic.update!(status: "blocked", lifecycle_status: "dormant")
        TopicStatusEvent.create!(
          topic: topic,
          lifecycle_status: "dormant",
          occurred_at: Time.current,
          evidence_type: "hollow_appearance_backfill",
          notes: "Blocked — 0 appearances remaining after backfill pruning."
        )
        puts "  BLOCK: #{topic.name} (0 left)"
      when 1
        topic.update!(lifecycle_status: "dormant")
        TopicStatusEvent.create!(
          topic: topic,
          lifecycle_status: "dormant",
          occurred_at: Time.current,
          evidence_type: "hollow_appearance_backfill",
          notes: "Demoted — only 1 appearance remaining after backfill pruning."
        )
        puts "  DORMANT: #{topic.name} (1 left)"
      else
        unless topic.resident_impact_admin_locked?
          Topics::GenerateTopicBriefingJob.perform_later(topic_id: topic.id)
        end
        puts "  REBRIEF: #{topic.name} (#{remaining} left)"
      end
    end

    puts "\nDone."
  end
end
