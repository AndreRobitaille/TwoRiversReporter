class ExtractTopicsJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    items = meeting.agenda_items.includes(meeting_documents: :extractions).order(:order_index)

    if items.empty?
      Rails.logger.info "No agenda items for Meeting #{meeting_id} to tag."
      return
    end

    # Format items for AI — enriched with linked document text
    items_text = items.map do |item|
      parts = []
      parts << "ID: #{item.id}"
      parts << "Title: #{item.title}"
      parts << "Summary: #{item.summary}" if item.summary.present?

      # Include linked document text (truncated per doc)
      item.meeting_documents.each do |doc|
        next if doc.extracted_text.blank?
        parts << "Attached Document (#{doc.document_type}): #{doc.extracted_text.truncate(2000, separator: ' ')}"
      end

      parts.join("\n")
    end.join("\n---\n")

    # Retrieve community context for extraction
    community_context = retrieve_community_context

    # Build meeting-level document context (packets/minutes not linked to specific items)
    meeting_docs_context = build_meeting_document_context(meeting, items)

    # Get existing approved topic names to reduce duplicates
    existing_topics = Topic.approved.pluck(:name)

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_topics(
      items_text,
      community_context: community_context,
      existing_topics: existing_topics,
      meeting_documents_context: meeting_docs_context
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

      # Pass 2: Refine catch-all ordinance topics into substantive civic concerns
      refine_catchall_topics(meeting, ai_service, existing_topics)

      # Schedule auto-triage with delay so extraction jobs from the same scraper run
      # complete before triage fires. Multiple enqueues are safe — the job is idempotent.
      Topics::AutoTriageJob.set(wait: 3.minutes).perform_later

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse topics JSON for Meeting #{meeting_id}: #{e.message}"
    end
  end

  private

  CATCHALL_TOPIC_NAMES = %w[
    height\ and\ area\ exceptions
  ].freeze

  def refine_catchall_topics(meeting, ai_service, existing_topics)
    catchall_links = AgendaItemTopic
      .joins(:topic)
      .where(agenda_item_id: meeting.agenda_items.select(:id))
      .where(topics: { canonical_name: CATCHALL_TOPIC_NAMES })
      .includes(:agenda_item, :topic)

    return if catchall_links.empty?

    catchall_links.each do |link|
      item = link.agenda_item
      doc_text = gather_item_document_text(item, meeting)
      next if doc_text.blank?

      begin
        result = ai_service.refine_catchall_topic(
          item_title: item.title,
          item_summary: item.summary,
          catchall_topic: link.topic.name,
          document_text: doc_text,
          existing_topics: existing_topics
        )

        data = JSON.parse(result)
        next unless data["action"] == "replace"

        new_name = data["topic_name"]
        next if new_name.blank?

        new_topic = Topics::FindOrCreateService.call(new_name)
        next unless new_topic

        # Replace the catch-all tag with the substantive topic
        link.destroy!
        AgendaItemTopic.find_or_create_by!(agenda_item: item, topic: new_topic)
        Rails.logger.info "Refined catch-all '#{link.topic.name}' -> '#{new_topic.name}' for AgendaItem #{item.id}"
      rescue JSON::ParserError, Faraday::Error => e
        Rails.logger.error "Refinement failed for AgendaItem #{item.id}: #{e.class} #{e.message}"
      end
    end
  end

  def gather_item_document_text(item, meeting)
    parts = []

    # Item-linked documents
    item.meeting_documents.each do |doc|
      next if doc.extracted_text.blank?
      parts << doc.extracted_text.truncate(2000, separator: " ")
    end

    # Meeting-level packet/minutes
    meeting.meeting_documents.where(document_type: %w[packet_pdf minutes_pdf]).each do |doc|
      next if doc.extracted_text.blank?
      parts << doc.extracted_text.truncate(4000, separator: " ")
    end

    parts.join("\n---\n")
  end

  def build_meeting_document_context(meeting, items)
    # Find document IDs already linked to specific agenda items
    linked_doc_ids = AgendaItemDocument
      .where(agenda_item_id: items.map(&:id))
      .pluck(:meeting_document_id)

    # Load meeting-level documents (packet/minutes) NOT linked to any item
    meeting_docs = meeting.meeting_documents
      .where(document_type: %w[packet_pdf minutes_pdf])
      .where.not(id: linked_doc_ids)
      .where.not(extracted_text: [ nil, "" ])

    return "" if meeting_docs.empty?

    meeting_docs.map do |doc|
      "#{doc.document_type}: #{doc.extracted_text.truncate(8000, separator: ' ')}"
    end.join("\n---\n")
  end

  def retrieve_community_context
    retrieval = RetrievalService.new
    results = retrieval.retrieve_context("Two Rivers community values resident concerns topic extraction", limit: 5)
    retrieval.format_context(results)
  rescue => e
    Rails.logger.warn "Failed to retrieve community context for extraction: #{e.message}"
    ""
  end
end
