module Admin
  class TranscriptImportsController < BaseController
    helper_method :meeting_option_label, :meeting_filter_text

    def show
      @meetings = Meeting.includes(:committee).order(starts_at: :desc).limit(250)
      @transcript_imports = TranscriptImport.includes(:meeting, :meeting_document).recent_first.limit(25)
      @selected_meeting_id = params.dig(:transcript_import, :meeting_id).presence || params[:meeting_id].presence
      @selected_youtube_url = params.dig(:transcript_import, :youtube_url).presence || params[:youtube_url].presence
    end

    def create
      meeting = Meeting.find_by(id: transcript_import_params[:meeting_id])
      unless meeting
        redirect_to admin_transcript_imports_path, alert: "Choose a valid meeting."
        return
      end

      youtube_url = transcript_import_params[:youtube_url].to_s.strip
      unless Documents::TranscriptDownloader.valid_url?(youtube_url)
        redirect_to admin_transcript_imports_path(meeting_id: meeting.id, youtube_url: youtube_url), alert: "Enter a valid YouTube watch URL."
        return
      end

      transcript_import = TranscriptImport.create!(meeting: meeting, youtube_url: youtube_url, status: "queued")
      Admin::TranscriptImportWorkflowJob.perform_later(transcript_import.id)

      redirect_to admin_transcript_imports_path, notice: "Transcript import workflow queued."
    end

    def check_url
      youtube_url = params.dig(:transcript_import, :youtube_url).to_s.strip.presence || params[:youtube_url].to_s.strip
      precheck = Documents::TranscriptDownloader.precheck(youtube_url)
      redirect_params = { youtube_url: youtube_url }
      redirect_params[:meeting_id] = params.dig(:transcript_import, :meeting_id).presence || params[:meeting_id].presence

      if precheck.status == :captions_available
        redirect_to admin_transcript_imports_path(redirect_params), notice: precheck.message
      else
        redirect_to admin_transcript_imports_path(redirect_params), alert: precheck.message
      end
    end

    def meeting_option_label(meeting)
      committee_name = meeting.committee&.name.presence || meeting.body_name.presence || "Meeting"
      meeting_date = meeting.starts_at&.strftime("%b %-d, %Y") || "No date"
      "#{committee_name} — #{meeting_date} — Meeting ##{meeting.id}"
    end

    def meeting_filter_text(meeting)
      [ meeting.id, meeting.body_name, meeting.committee&.name, meeting.starts_at&.strftime("%B %-d, %Y") ].compact.join(" ")
    end

    private

    def transcript_import_params
      params.fetch(:transcript_import, {}).permit(:meeting_id, :youtube_url)
    end
  end
end
