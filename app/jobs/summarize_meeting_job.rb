class SummarizeMeetingJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    ai_service = Ai::OpenAiService.new

    # 1. Check for Minutes (Highest Priority for "What Happened")
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")
    if minutes_doc&.extracted_text.present?
      summary_text = ai_service.summarize_minutes(minutes_doc.extracted_text)
      save_summary(meeting, "minutes_recap", summary_text)
      return
    end

    # 2. Check for Packet (Priority for "What's Coming Up")
    packet_doc = meeting.meeting_documents.where("document_type LIKE ?", "%packet%").first
    if packet_doc
      summary_text = nil
      if packet_doc.extractions.any?
        summary_text = ai_service.summarize_packet_with_citations(packet_doc.extractions)
      elsif packet_doc.extracted_text.present?
        summary_text = ai_service.summarize_packet(packet_doc.extracted_text)
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

  def save_summary(meeting, type, content)
    summary = meeting.meeting_summaries.find_or_initialize_by(summary_type: type)
    summary.content = content
    summary.save!
  end
end
