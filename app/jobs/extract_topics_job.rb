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

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_topics(items_text)

    begin
      data = JSON.parse(json_response)
      classifications = data["items"] || []

      classifications.each do |c_data|
        item_id = c_data["id"]
        category = c_data["category"]
        tags = c_data["tags"] || []
        confidence = c_data["confidence"]&.to_f

        # Find item
        item = AgendaItem.find_by(id: item_id)
        next unless item

        if confidence && confidence < 0.5
          Rails.logger.warn "Low-confidence topic classification (#{confidence}) for AgendaItem #{item_id}: category=#{category}, tags=#{tags.inspect}"
        end

        # Create topics
        all_topics = [ category ] + tags
        all_topics.each do |topic_name|
          next if topic_name.blank?

          # Find or Create Topic
          topic = Topics::FindOrCreateService.call(topic_name)
          next unless topic

          # Link
          AgendaItemTopic.find_or_create_by!(agenda_item: item, topic: topic)
        end
      end

      Rails.logger.info "Tagged #{classifications.size} items for Meeting #{meeting_id}"

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse topics JSON for Meeting #{meeting_id}: #{e.message}"
    end
  end
end
