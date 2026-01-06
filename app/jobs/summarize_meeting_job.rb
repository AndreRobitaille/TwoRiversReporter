class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    ai_service = ::Ai::OpenAiService.new
    retrieval_service = RetrievalService.new

    # Build retrieval query
    query = build_retrieval_query(meeting)
    retrieved_chunks = retrieval_service.retrieve_context(query)
    formatted_context = retrieval_service.format_context(retrieved_chunks).split("\n\n")

    # 1. Check for Minutes (Highest Priority for "What Happened")
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")
    if minutes_doc&.extracted_text.present?
      summary_text = ai_service.summarize_minutes(minutes_doc.extracted_text, context_chunks: formatted_context)
      save_summary(meeting, "minutes_recap", summary_text)
      return
    end

    # 2. Check for Packet (Priority for "What's Coming Up")
    packet_doc = meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first
    if packet_doc
      summary_text = nil
      if packet_doc.extractions.any?
        summary_text = ai_service.summarize_packet_with_citations(packet_doc.extractions, context_chunks: formatted_context)
      elsif packet_doc.extracted_text.present?
        summary_text = ai_service.summarize_packet(packet_doc.extracted_text, context_chunks: formatted_context)
      end

      if summary_text
        save_summary(meeting, "packet_analysis", summary_text)
        nil
      end
    end

    # 3. Fallback: Agenda Only?
    # We already have AgendaItems parsed, so an "Agenda Overview" might just be redundant unless we want a prose summary.
    # For now, we skip if only agenda exists.
  end

  private

  def build_retrieval_query(meeting)
    parts = [ "#{meeting.body_name} meeting on #{meeting.starts_at&.to_date}" ]

    # Add top agenda items if available
    if meeting.agenda_items.any?
      parts << "Agenda: " + meeting.agenda_items.order(:order_index).limit(5).pluck(:title).join(", ")
    end

    parts.join("\n")
  end

  def save_summary(meeting, type, content)
    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.content = content
    summary.save!
  end
end
