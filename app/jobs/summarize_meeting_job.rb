class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # 1. Meeting-Level Summary (Minutes or Packet)
    generate_meeting_summary(meeting, ai_service, retrieval_service)

    # 2. Topic-Level Summaries
    generate_topic_summaries(meeting, ai_service, retrieval_service)
  end

  private

  def generate_meeting_summary(meeting, ai_service, retrieval_service)
    query = build_retrieval_query(meeting)
    retrieved_chunks = retrieval_service.retrieve_context(query)
    formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")
    kb_context = ai_service.prepare_kb_context(formatted_context)

    # Prefer minutes (authoritative) over packet
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")
    if minutes_doc&.extracted_text.present?
      json_str = ai_service.analyze_meeting_content(minutes_doc.extracted_text, kb_context, "minutes", source: meeting)
      save_summary(meeting, "minutes_recap", json_str)
      return
    end

    # Fall back to packet
    packet_doc = meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first
    if packet_doc
      doc_text = if packet_doc.extractions.any?
        ai_service.prepare_doc_context(packet_doc.extractions)
      elsif packet_doc.extracted_text.present?
        packet_doc.extracted_text
      end

      if doc_text
        json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
        save_summary(meeting, "packet_analysis", json_str)
      end
    end
  end

  def generate_topic_summaries(meeting, ai_service, retrieval_service)
    # Only process approved topics to avoid noise
    meeting.topics.approved.distinct.each do |topic|
      # Retrieve context specific to the topic
      query_builder = Topics::RetrievalQueryBuilder.new(topic, meeting)
      query = query_builder.build_query

      retrieved_chunks = retrieval_service.retrieve_topic_context(topic: topic, query_text: query, limit: 5, max_chars: 6000)
      formatted_context = retrieval_service.format_topic_context(retrieved_chunks)

      builder = Topics::SummaryContextBuilder.new(topic, meeting)
      context_json = builder.build_context_json(kb_context_chunks: formatted_context)

      analysis_json_str = ai_service.analyze_topic_summary(context_json, source: topic)

      # Parse safely for storage
      analysis_json = begin
        JSON.parse(analysis_json_str)
      rescue JSON::ParserError
        Rails.logger.error("Failed to parse topic summary analysis for Topic #{topic.id}")
        {}
      end

      # Validate citations
      analysis_json = validate_analysis_json(analysis_json, context_json[:citation_ids])

      markdown_content = ai_service.render_topic_summary(analysis_json.to_json, source: topic)

      save_topic_summary(meeting, topic, markdown_content, analysis_json)

      # Propagate resident impact score to topic
      if analysis_json["resident_impact"].is_a?(Hash)
        score = analysis_json["resident_impact"]["score"].to_i
        topic.update_resident_impact_from_ai(score) if score.between?(1, 5)
      end

      # Trigger full briefing generation
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: meeting.id
      )
    end
  end

  def validate_analysis_json(json, allowed_citation_ids)
    allowed_ids = Array(allowed_citation_ids).compact

    # Ensure factual_record entries have citations and are in allowed list
    if json["factual_record"].is_a?(Array)
      json["factual_record"].select! do |entry|
        citations = entry["citations"]
        valid = citations.is_a?(Array) && citations.any? do |citation|
          next false unless citation.is_a?(Hash)
          allowed_ids.include?(citation["citation_id"])
        end

        unless valid
          Rails.logger.warn("Dropping uncited or invalid factual claim: #{entry['statement']}")
        end

        valid
      end
    end

    # Ensure institutional_framing entries have citations and are in allowed list
    if json["institutional_framing"].is_a?(Array)
      json["institutional_framing"].select! do |entry|
        citations = entry["citations"]
        valid = citations.is_a?(Array) && citations.any? do |citation|
          next false unless citation.is_a?(Hash)
          allowed_ids.include?(citation["citation_id"])
        end

        unless valid
          Rails.logger.warn("Dropping uncited or invalid framing claim: #{entry['statement']}")
        end

        valid
      end
    end

    json
  end


  def build_retrieval_query(meeting)
    parts = [ "#{meeting.body_name} meeting on #{meeting.starts_at&.to_date}" ]

    # Add top agenda items if available
    if meeting.agenda_items.any?
      parts << "Agenda: " + meeting.agenda_items.order(:order_index).limit(5).pluck(:title).join(", ")
    end

    parts.join("\n")
  end

  def save_summary(meeting, type, json_str)
    generation_data = begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse meeting summary JSON: #{e.message}"
      {}
    end

    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.generation_data = generation_data
    summary.content = nil
    summary.save!
  end

  def save_topic_summary(meeting, topic, content, generation_data)
    summary = meeting.topic_summaries.find_or_initialize_by(topic: topic, summary_type: "topic_digest")
    summary.content = content
    summary.generation_data = generation_data
    summary.save!
  end
end
