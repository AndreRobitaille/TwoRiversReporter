class ExtractTopicsJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    items = meeting.agenda_items.order(:order_index)

    if items.empty?
      Rails.logger.info "No agenda items for Meeting #{meeting_id} to tag."
      return
    end

    # Format items for AI
    items_text = items.map do |item|
      "ID: #{item.id}\nTitle: #{item.title}\nSummary: #{item.summary}\n"
    end.join("\n---\n")

    # Retrieve community context for extraction
    community_context = retrieve_community_context

    # Get existing approved topic names to reduce duplicates
    existing_topics = Topic.approved.pluck(:name)

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_topics(
      items_text,
      community_context: community_context,
      existing_topics: existing_topics
    )

    begin
      data = JSON.parse(json_response)
      classifications = data["items"] || []

      classifications.each do |c_data|
        item_id = c_data["id"]
        category = c_data["category"]
        tags = c_data["tags"] || []
        confidence = c_data["confidence"]&.to_f
        topic_worthy = c_data.fetch("topic_worthy", true)

        # Find item
        item = AgendaItem.find_by(id: item_id)
        next unless item

        if confidence && confidence < 0.5
          Rails.logger.warn "Low-confidence topic classification (#{confidence}) for AgendaItem #{item_id}: category=#{category}, tags=#{tags.inspect}"
        end

        # Skip administrative/procedural/routine items
        next if category == "Administrative"
        next if category == "Routine"

        # Skip items the AI determined are not topic-worthy
        next unless topic_worthy

        # Create topics from tags only (category is a broad grouping, not a topic)
        tags.each do |topic_name|
          next if topic_name.blank?

          topic = Topics::FindOrCreateService.call(topic_name)
          next unless topic

          AgendaItemTopic.find_or_create_by!(agenda_item: item, topic: topic)
        end
      end

      Rails.logger.info "Tagged #{classifications.size} items for Meeting #{meeting_id}"

      # Schedule auto-triage with delay so extraction jobs from the same scraper run
      # complete before triage fires. Multiple enqueues are safe — the job is idempotent.
      Topics::AutoTriageJob.set(wait: 3.minutes).perform_later

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse topics JSON for Meeting #{meeting_id}: #{e.message}"
    end
  end

  private

  def retrieve_community_context
    retrieval = RetrievalService.new
    results = retrieval.retrieve_context("Two Rivers community values resident concerns topic extraction", limit: 5)
    retrieval.format_context(results)
  rescue => e
    Rails.logger.warn "Failed to retrieve community context for extraction: #{e.message}"
    ""
  end
end
