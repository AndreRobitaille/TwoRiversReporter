module Admin
  class SummariesController < BaseController
    def show
      @total_meetings = Meeting.count
      @meetings_with_docs = Meeting.joins(:meeting_documents)
                                   .where(meeting_documents: { document_type: %w[minutes_pdf packet_pdf] })
                                   .where.not(meeting_documents: { extracted_text: [ nil, "" ] })
                                   .distinct
                                   .count
      @existing_summaries = MeetingSummary.count
    end

    def regenerate_all
      # Find meetings that have summarizable documents (minutes or packets with text)
      meeting_ids = Meeting.joins(:meeting_documents)
                           .where(meeting_documents: { document_type: %w[minutes_pdf packet_pdf] })
                           .where.not(meeting_documents: { extracted_text: [ nil, "" ] })
                           .distinct
                           .pluck(:id)

      # Queue jobs for each meeting
      meeting_ids.each do |meeting_id|
        SummarizeMeetingJob.perform_later(meeting_id)
      end

      redirect_to admin_summaries_path, notice: "Queued #{meeting_ids.size} meeting(s) for summary regeneration."
    end

    def regenerate_one
      meeting_id = params[:meeting_id]
      meeting = Meeting.find(meeting_id)

      SummarizeMeetingJob.perform_later(meeting.id)

      redirect_back fallback_location: admin_summaries_path, notice: "Queued Meeting ##{meeting.id} for summary regeneration."
    end
  end
end
