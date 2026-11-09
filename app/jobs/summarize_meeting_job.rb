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
    return if generate_meeting_summary(meeting, ai_service, retrieval_service) == false

    # 2. Establish deterministic continuity before capturing topic dependencies.
    Topics::UpdateContinuityJob.perform_now(meeting_id: meeting.id)
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

    summary = generate_agenda_preview_summary(meeting, agenda_doc, ai_service, retrieval_service)
    enqueue_briefing_refresh(meeting) if summary
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

    topic_context = Topics::AgendaBriefingContext.new(agenda_doc.extracted_text)
    combined_context = [ topic_context.text, kb_context ].reject(&:blank?).join("\n\n")

    analyze_and_save_summary(meeting, [ agenda_doc ], ai_service, combined_context,
      type: "agenda", summary_type: "agenda_preview", source_type: "agenda", topic_context: topic_context)
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
      summary = analyze_and_save_summary(meeting, documents, ai_service, kb_context,
        type: "minutes", summary_type: "minutes_recap", source_type: source_type)
      return false unless summary
      meeting.meeting_summaries.where(summary_type: %w[transcript_recap packet_analysis agenda_preview]).destroy_all
      MatchCampaignIssueEvidenceJob.perform_later
    elsif transcript_doc&.extracted_text.present?
      summary = analyze_and_save_summary(meeting, [ background_doc, transcript_doc ].compact, ai_service, kb_context,
        type: "transcript", summary_type: "transcript_recap", source_type: "transcript")
      return false unless summary
      meeting.meeting_summaries.where(summary_type: %w[packet_analysis agenda_preview]).destroy_all
    elsif packet_doc
      summary = analyze_and_save_summary(meeting, [ packet_doc ], ai_service, kb_context,
        type: "packet", summary_type: "packet_analysis", source_type: "packet")
      return false unless summary
      meeting.meeting_summaries.where(summary_type: "agenda_preview").destroy_all
    end
  end

  def analyze_and_save_summary(meeting, documents, ai_service, kb_context, type:, summary_type:, source_type:, topic_context: nil)
    catalog = Citations::SourceCatalog.new(meeting: meeting, documents: documents)
    return unless Topics::GenerationEvidence.sources_current?(catalog.sources)

    expected = Meetings::SummaryPublication.version(meeting.meeting_summaries.find_by(summary_type: summary_type))
    motion_context = Meetings::MotionContext.capture(meeting.id)
    meeting_record_text = documents.select { |document| document.document_type.in?(%w[minutes_pdf minutes_html transcript]) }
      .map(&:extracted_text).join("\n\n")
    json_str = ai_service.analyze_meeting_content(catalog.text, kb_context, type,
      source: motion_context.meeting, source_catalog: catalog.sources,
      meeting_record_text: meeting_record_text,
      participant_context: participant_context_for(motion_context.meeting), motion_context: motion_context.text)
    Meetings::SummaryPublication.publish(meeting: meeting, summary_type: summary_type, expected: expected,
      sources: catalog.sources, topic_context: topic_context, motion_context: motion_context) do
      save_summary(meeting, summary_type, json_str, source_catalog: catalog.sources,
        source_type: source_type, framing: compute_framing(motion_context.meeting, type), motion_context_manifest: motion_context.manifest, topic_context_manifest: topic_context&.manifest)
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
      summary = Topics::GenerateSummary.new(topic, meeting, ai_service: ai_service, retrieval_service: retrieval_service).call
      next unless summary

      # Trigger full briefing generation
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: meeting.id
      )
    rescue JSON::ParserError
      Rails.logger.error("Failed to parse topic summary analysis for Topic #{topic.id}")
    end
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

  def save_summary(meeting, type, json_str, source_catalog:, source_type: nil, framing: nil, motion_context_manifest: nil, topic_context_manifest: nil)
    generation_data = begin
      JSON.parse(json_str)
    rescue JSON::ParserError => e
      raise Citations::SourceCatalog::InvalidSource, "Invalid meeting summary JSON: #{e.message}"
    end

    Citations::MeetingAnalysis.validate!(generation_data, meeting: meeting, catalog: source_catalog)
    generation_data["source_type"] = source_type if source_type
    generation_data["framing"] = framing if framing
    generation_data["motion_context_manifest"] = motion_context_manifest
    generation_data["topic_context_manifest"] = topic_context_manifest

    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.generation_data = generation_data
    summary.content = nil
    summary.evidence_withdrawn_at = nil
    summary.save!
    enqueue_generated_image_job_for_meeting(summary)
    summary
  end

  def participant_context_for(meeting)
    agenda_doc = meeting.latest_document("agenda_pdf")
    agenda_text = agenda_doc&.extracted_text
    Meetings::ParticipantsContextBuilder.new(meeting, agenda_text).build
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
