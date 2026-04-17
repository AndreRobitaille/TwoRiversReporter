class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  def perform(meeting_id, mode: :full)
    meeting = Meeting.find(meeting_id)

    case mode
    when :full
      run_full_mode(meeting)
    when :agenda_preview
      run_agenda_preview_mode(meeting)
    else
      raise ArgumentError, "Unknown mode: #{mode.inspect}"
    end
  end

  private

  def run_full_mode(meeting)
    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # 1. Meeting-Level Summary (Minutes or Packet)
    generate_meeting_summary(meeting, ai_service, retrieval_service)

    # 2. Topic-Level Summaries
    generate_topic_summaries(meeting, ai_service, retrieval_service)

    # 3. Prune hollow topic appearances based on the new summary's
    #    activity_level signal. Runs before knowledge extraction so
    #    downstream jobs see the cleaned-up appearance set.
    PruneHollowAppearancesJob.perform_later(meeting.id)

    # 4. Knowledge Extraction (downstream, never blocks summarization)
    ExtractKnowledgeJob.perform_later(meeting.id)
  end

  def run_agenda_preview_mode(meeting)
    agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")
    return if agenda_doc.nil? || agenda_doc.extracted_text.blank?

    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    generate_agenda_preview_summary(meeting, agenda_doc, ai_service, retrieval_service)
    enqueue_briefing_refresh(meeting)
  end

  def generate_agenda_preview_summary(meeting, agenda_doc, ai_service, retrieval_service)
    query = build_retrieval_query(meeting)
    retrieved_chunks = begin
      retrieval_service.retrieve_context(query)
    rescue => e
      Rails.logger.warn("Context retrieval failed for Meeting #{meeting.id}: #{e.message}")
      []
    end
    formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")
    kb_context = ai_service.prepare_kb_context(formatted_context)

    topic_context = agenda_topic_context(agenda_doc.extracted_text)
    combined_context = [ topic_context, kb_context ].reject(&:blank?).join("\n\n")

    json_str = ai_service.analyze_meeting_content(agenda_doc.extracted_text, combined_context, "agenda", source: meeting)
    save_summary(
      meeting,
      "agenda_preview",
      json_str,
      source_type: "agenda",
      framing: compute_framing(meeting, "agenda")
    )
  end

  AGENDA_TOPIC_MIN_TOKEN_OVERLAP = 3
  AGENDA_TOPIC_MIN_IMPACT = 3
  AGENDA_TOPIC_MAX_HITS = 6
  AGENDA_TOPIC_STOPWORDS = Set.new(%w[
    a an the of and or but to for in on at by with from as is be are was were
    been being this that these those it its their our your my me us we they he
    she his her them have has had do does did not no so if then than which who
    whom whose where when why how all any each every some other into out up down
    off over under same own more most less few many such new old
  ]).freeze

  def agenda_topic_context(agenda_text)
    return "" if agenda_text.blank?
    agenda_tokens = significant_tokens(agenda_text)
    return "" if agenda_tokens.size < AGENDA_TOPIC_MIN_TOKEN_OVERLAP

    topics = Topic.approved
      .where("resident_impact_score >= ?", AGENDA_TOPIC_MIN_IMPACT)
      .joins(:topic_briefing)
      .where.not(topic_briefings: { editorial_content: [ nil, "" ] })
      .includes(:topic_aliases, :topic_briefing)

    scored = topics.filter_map do |topic|
      needles = [ topic.name ] + topic.topic_aliases.map(&:name)
      best_overlap = needles.map do |needle|
        needle_tokens = significant_tokens(needle)
        next 0 if needle_tokens.size < AGENDA_TOPIC_MIN_TOKEN_OVERLAP
        (needle_tokens & agenda_tokens).size
      end.max || 0

      next nil if best_overlap < AGENDA_TOPIC_MIN_TOKEN_OVERLAP
      [ topic, best_overlap ]
    end

    hits = scored
      .sort_by { |topic, overlap| [ -topic.resident_impact_score.to_i, -overlap ] }
      .first(AGENDA_TOPIC_MAX_HITS)
      .map(&:first)

    return "" if hits.empty?

    sections = hits.map do |topic|
      briefing = topic.topic_briefing
      parts = [ "## Known topic: #{topic.name}" ]
      parts << "Impact score: #{topic.resident_impact_score}"
      parts << "Current state: #{briefing.headline}" if briefing.headline.present?
      parts << "Coming up: #{briefing.upcoming_headline}" if briefing.upcoming_headline.present?
      parts << briefing.editorial_content.to_s.truncate(1200) if briefing.editorial_content.present?
      parts.join("\n")
    end

    <<~TOPIC_CONTEXT.strip
      <topic_briefings>
      The following topics are ongoing civic concerns in Two Rivers that share content words with the agenda text. Use them to ground your analysis where clearly relevant to an agenda item — residents already recognize these issues. These are established context, not outcomes from this meeting. Ignore entries that don't actually line up with any item.

      #{sections.join("\n\n")}
      </topic_briefings>
    TOPIC_CONTEXT
  end

  def significant_tokens(text)
    Set.new(
      text.to_s.downcase.scan(/[a-z]+/).filter_map do |word|
        next if word.length < 3
        next if AGENDA_TOPIC_STOPWORDS.include?(word)
        word.sub(/s\z/, "")
      end
    )
  end

  def enqueue_briefing_refresh(meeting)
    Topic.approved
      .joins(:agenda_item_topics)
      .where(agenda_item_topics: { agenda_item_id: meeting.agenda_items.substantive.select(:id) })
      .distinct
      .find_each do |topic|
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: meeting.id
      )
    end
  end

  def generate_meeting_summary(meeting, ai_service, retrieval_service)
    query = build_retrieval_query(meeting)
    retrieved_chunks = begin
      retrieval_service.retrieve_context(query)
    rescue => e
      Rails.logger.warn("Context retrieval failed for Meeting #{meeting.id}: #{e.message}")
      []
    end
    formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")
    kb_context = ai_service.prepare_kb_context(formatted_context)

    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")
    transcript_doc = meeting.meeting_documents.find_by(document_type: "transcript")

    # Priority 1: Minutes (authoritative), optionally supplemented by transcript
    if minutes_doc&.extracted_text.present?
      input_text = minutes_doc.extracted_text
      source_type = "minutes"

      if transcript_doc&.extracted_text.present?
        input_text += "\n\n--- Additional context from meeting recording transcript ---\n\n" +
          transcript_doc.extracted_text.truncate(15_000)
        source_type = "minutes_with_transcript"
      end

      json_str = ai_service.analyze_meeting_content(input_text, kb_context, "minutes", source: meeting)
      summary = save_summary(meeting, "minutes_recap", json_str, source_type: source_type, framing: compute_framing(meeting, "minutes"))

      # Clean up superseded summaries now that minutes exist
      meeting.meeting_summaries.where(summary_type: %w[transcript_recap packet_analysis agenda_preview]).destroy_all
      return
    end

    # Priority 2: Transcript (when no minutes available)
    if transcript_doc&.extracted_text.present?
      json_str = ai_service.analyze_meeting_content(transcript_doc.extracted_text, kb_context, "transcript", source: meeting)
      save_summary(meeting, "transcript_recap", json_str, source_type: "transcript", framing: compute_framing(meeting, "transcript"))

      # Clean up superseded packet preview / agenda preview
      meeting.meeting_summaries.where(summary_type: %w[packet_analysis agenda_preview]).destroy_all
      return
    end

    # Priority 3: Fall back to packet
    packet_doc = meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first
    if packet_doc
      doc_text = if packet_doc.extractions.any?
        ai_service.prepare_doc_context(packet_doc.extractions)
      elsif packet_doc.extracted_text.present?
        packet_doc.extracted_text
      end

      if doc_text
        json_str = ai_service.analyze_meeting_content(doc_text, kb_context, "packet", source: meeting)
        save_summary(meeting, "packet_analysis", json_str, framing: compute_framing(meeting, "packet"))
        # Clean up superseded agenda preview
        meeting.meeting_summaries.where(summary_type: "agenda_preview").destroy_all
      else
        Rails.logger.warn("No extractable text for packet document on Meeting #{meeting.id}")
      end
    end
  end

  def generate_topic_summaries(meeting, ai_service, retrieval_service)
    # Only process approved topics to avoid noise
    # SummaryContextBuilder now filters structural rows so topic summaries
    # only see substantive agenda evidence.
    Topic.approved
      .joins(:agenda_item_topics)
      .where(agenda_item_topics: { agenda_item_id: meeting.agenda_items.substantive.select(:id) })
      .distinct
      .each do |topic|
      # Retrieve context specific to the topic
      query_builder = Topics::RetrievalQueryBuilder.new(topic, meeting)
      query = query_builder.build_query

      retrieved_chunks = retrieval_service.retrieve_topic_context(topic: topic, query_text: query, limit: 5, max_chars: 6000)
      formatted_context = retrieval_service.format_topic_context(retrieved_chunks)

      builder = Topics::SummaryContextBuilder.new(topic, meeting)
      context_json = builder.build_context_json(kb_context_chunks: formatted_context)

      analysis_json_str = ai_service.analyze_topic_summary(context_json, source: topic)

      unless analysis_json_str.present?
        Rails.logger.error("Empty response from analyze_topic_summary for Topic #{topic.id}")
        next
      end

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


  def compute_framing(meeting, type)
    starts_at = meeting.starts_at
    if starts_at && starts_at > Time.current
      "preview"
    elsif type == "minutes" || type == "transcript"
      "recap"
    else
      "stale_preview"
    end
  end

  def build_retrieval_query(meeting)
    parts = [ "#{meeting.body_name} meeting on #{meeting.starts_at&.to_date}" ]

    # Add top agenda items if available
    agenda_titles = meeting.agenda_items
      .substantive
      .includes(:parent)
      .order(:order_index)
      .limit(5)
      .map(&:display_context_title)

    if agenda_titles.any?
      parts << "Agenda: " + agenda_titles.join(", ")
    end

    parts.join("\n")
  end

  def save_summary(meeting, type, json_str, source_type: nil, framing: nil)
    generation_data = begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse meeting summary JSON: #{e.message}"
      {}
    end

    generation_data["source_type"] = source_type if source_type
    generation_data["framing"] = framing if framing

    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.generation_data = generation_data
    summary.content = nil
    summary.save!
    summary
  end

  def save_topic_summary(meeting, topic, content, generation_data)
    summary = meeting.topic_summaries.find_or_initialize_by(topic: topic, summary_type: "topic_digest")
    summary.content = content
    summary.generation_data = generation_data
    summary.save!
  end
end
