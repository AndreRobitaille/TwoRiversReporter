namespace :agenda_previews do
  desc "Backfill agenda_preview summaries for meetings that have agenda_pdf but no summary"
  task backfill: :environment do
    scope = Meeting.joins(:meeting_documents)
      .where(meeting_documents: { document_type: "agenda_pdf" })
      .where.missing(:meeting_summaries)
      .distinct

    total = scope.count
    puts "Enqueueing agenda_preview summarization for #{total} meetings..."

    enqueued = 0
    scope.find_each do |meeting|
      agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")
      next if agenda_doc&.extracted_text.blank?

      SummarizeMeetingJob.perform_later(meeting.id, mode: :agenda_preview)
      enqueued += 1
    end

    puts "Enqueued #{enqueued} jobs (skipped #{total - enqueued} meetings with blank agenda text)."
  end
end
