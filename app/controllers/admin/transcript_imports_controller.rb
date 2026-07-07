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

      srt_file = transcript_import_upload
      unless valid_srt_upload?(srt_file)
        redirect_to admin_transcript_imports_path(meeting_id: meeting.id, youtube_url: youtube_url), alert: "Upload an SRT file, or remove the selected file before importing."
        return
      end

      transcript_import = TranscriptImport.create!(meeting: meeting, youtube_url: youtube_url, status: "queued")
      transcript_import.srt_file.attach(srt_file) if srt_file.present?
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

    def valid_srt_upload?(upload)
      return true if upload.blank?
      return false unless upload.respond_to?(:original_filename)
      return false unless File.extname(upload.original_filename.to_s).casecmp(".srt").zero?
      return false if upload.respond_to?(:size) && upload.size.to_i <= 0
      return false unless allowed_srt_content_type?(upload.content_type)

      true
    end

    def allowed_srt_content_type?(content_type)
      content_type.to_s.split(";").first.strip.then do |normalized|
        %w[text/srt application/x-subrip text/plain application/octet-stream].include?(normalized)
      end
    end

    def transcript_import_params
      params.fetch(:transcript_import, {}).permit(:meeting_id, :youtube_url)
    end

    def transcript_import_upload
      params.require(:transcript_import).fetch(:srt_file, nil)
    end
  end
end
