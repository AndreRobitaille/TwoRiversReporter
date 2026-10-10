class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  SUMMARY_PRIORITY = [
    [ "minutes_pdf", "minutes_recap" ],
    [ "transcript", "transcript_recap" ],
    [ "packet_pdf", "packet_analysis" ]
  ].freeze

  def perform(meeting_id, mode: :full, enqueue_followups: true)
    meeting = Meeting.find(meeting_id)

    case mode
    when :full
      run_full_mode(meeting, enqueue_followups: enqueue_followups)
    when :agenda_preview
      run_agenda_preview_mode(meeting)
    else
      raise ArgumentError, "Unknown mode: #{mode.inspect}"
    end
  end

  private

  def run_full_mode(meeting, enqueue_followups: true)
    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # 1. Meeting-Level Summary (Minutes or Packet)
    generate_meeting_summary(meeting, ai_service, retrieval_service)

    # 2. Topic-Level Summaries
    generate_topic_summaries(meeting, ai_service, retrieval_service)

    # 3. Prune hollow topic appearances based on the new summary's
    #    activity_level signal. Runs before knowledge extraction so
    #    downstream jobs see the cleaned-up appearance set.
    PruneHollowAppearancesJob.perform_later(meeting.id) if enqueue_followups

    # 4. Knowledge Extraction (downstream, never blocks summarization)
    ExtractKnowledgeJob.perform_later(meeting.id) if enqueue_followups
  end

  def run_agenda_preview_mode(meeting)
    agenda_doc = meeting.latest_document("agenda_pdf")
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

    analyze_and_save_summary(meeting, [ agenda_doc ], ai_service, combined_context,
      type: "agenda", summary_type: "agenda_preview", source_type: "agenda")
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

    minutes_doc = minutes_document_for(meeting)
    transcript_doc = meeting.latest_document("transcript")
    packet_doc = packet_document_for(meeting)
    background_doc = packet_doc || meeting.latest_documents("agenda_pdf", "agenda_html")
      .find { |document| document.extracted_text.present? }

    # Recaps retain official proposal evidence alongside the meeting record.
    if minutes_doc&.extracted_text.present?
      documents = [ minutes_doc, background_doc ].compact
      documents << transcript_doc if transcript_doc&.extracted_text.present?
      source_type = transcript_doc&.extracted_text.present? ? "minutes_with_transcript" : "minutes"
      analyze_and_save_summary(meeting, documents, ai_service, kb_context,
        type: "minutes", summary_type: "minutes_recap", source_type: source_type)
      meeting.meeting_summaries.where(summary_type: %w[transcript_recap packet_analysis agenda_preview]).destroy_all
    elsif transcript_doc&.extracted_text.present?
      analyze_and_save_summary(meeting, [ background_doc, transcript_doc ].compact, ai_service, kb_context,
        type: "transcript", summary_type: "transcript_recap", source_type: "transcript")
      meeting.meeting_summaries.where(summary_type: %w[packet_analysis agenda_preview]).destroy_all
    elsif packet_doc
      analyze_and_save_summary(meeting, [ packet_doc ], ai_service, kb_context,
        type: "packet", summary_type: "packet_analysis", source_type: "packet")
      meeting.meeting_summaries.where(summary_type: "agenda_preview").destroy_all
    end
  end

  def analyze_and_save_summary(meeting, documents, ai_service, kb_context, type:, summary_type:, source_type:)
    catalog = Citations::SourceCatalog.new(meeting: meeting, documents: documents)
    meeting_record_text = documents.select { |document| document.document_type.in?(%w[minutes_pdf minutes_html transcript]) }
      .map(&:extracted_text).join("\n\n")
    json_str = ai_service.analyze_meeting_content(catalog.text, kb_context, type,
      source: meeting, source_catalog: catalog.sources,
      meeting_record_text: meeting_record_text,
      participant_context: participant_context_for(meeting), motion_context: motion_context_for(meeting))
    save_summary(meeting, summary_type, json_str, source_catalog: catalog.sources,
      source_type: source_type, framing: compute_framing(meeting, type))
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
      analysis_json = validate_analysis_json(analysis_json, context_json[:citation_ids], context_json[:citation_references])

      analysis_json["source_catalog"] = context_json[:source_catalog].deep_dup
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

  def validate_analysis_json(json, allowed_citation_ids, citation_references = {})
    references = citation_references.slice(*Array(allowed_citation_ids).compact)
    Citations::TopicAnalysis.copy_references!(json, references: references,
      require_citations: %w[factual_record institutional_framing])
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

  def save_summary(meeting, type, json_str, source_catalog:, source_type: nil, framing: nil)
    generation_data = begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      raise Citations::SourceCatalog::InvalidSource, "Invalid meeting summary JSON: #{e.message}"
    end

    Citations::MeetingAnalysis.validate!(generation_data, meeting: meeting, catalog: source_catalog)
    generation_data["source_type"] = source_type if source_type
    generation_data["framing"] = framing if framing

    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.generation_data = generation_data
    summary.content = nil
    summary.save!
    enqueue_generated_image_job_for_meeting(summary)
    summary
  end

  def save_topic_summary(meeting, topic, content, generation_data)
    summary = meeting.topic_summaries.find_or_initialize_by(topic: topic, summary_type: "topic_digest")
    summary.content = content
    summary.generation_data = generation_data
    summary.save!
  end

  def participant_context_for(meeting)
    agenda_doc = meeting.latest_document("agenda_pdf")
    agenda_text = agenda_doc&.extracted_text
    Meetings::ParticipantsContextBuilder.new(meeting, agenda_text).build
  end

  def motion_context_for(meeting)
    motions = meeting.motions.includes(:agenda_item, :votes).order(:id).to_a
    return "No structured motion extraction available." if motions.empty?

    lines = motions.map do |motion|
      item = motion.agenda_item&.title || "No linked agenda item"
      vote_counts = motion.votes.group_by(&:value).transform_values(&:count)
      vote_text = if vote_counts.any?
        vote_counts.sort.map { |value, count| "#{value}=#{count}" }.join(", ")
      else
        "no individual votes recorded"
      end

      "- #{item}: #{motion.outcome} — #{motion.description} (#{vote_text})"
    end

    <<~TEXT.strip
      Structured motions extracted from the same meeting minutes. Use this as grounding for item decision and vote fields when it conflicts with noisy prose in the minutes.
      #{lines.join("\n")}
    TEXT
  end

  def self.summary_repair_needed?(meeting)
    source_type, summary_type = summary_target_for(meeting)
    return false if source_type.nil?

    summary = meeting.meeting_summaries.where(summary_type: summary_type).order(id: :desc).first
    return true if summary.nil?

    summary.content.blank? && summary.generation_data.blank?
  end

  def self.summary_target_for(meeting)
    SUMMARY_PRIORITY.each do |document_type, summary_type|
      doc = case document_type
      when "packet_pdf"
        meeting.meeting_documents.where("document_type LIKE ?", "%packet%").where.not(extracted_text: [ nil, "" ]).exists?
      else
        meeting.meeting_documents.where(document_type: document_type).where.not(extracted_text: [ nil, "" ]).exists?
      end
      return [ document_type, summary_type ] if doc
    end

    [ nil, nil ]
  end

  def minutes_document_for(meeting)
    meeting.latest_document("minutes_pdf")
  end

  def packet_document_for(meeting)
    meeting.latest_documents("packet_pdf", "packet_html")
      .find { |document| document.extracted_text.present? }
  end

  def enqueue_generated_image_job_for_meeting(summary)
    return unless GeneratedImages::Config.enabled?

    GeneratedImages::GenerateForMeetingJob.perform_later(summary.meeting_id)
  end
end
