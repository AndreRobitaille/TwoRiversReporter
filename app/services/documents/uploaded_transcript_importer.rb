module Documents
  class UploadedTranscriptImporter
    ImportError = Class.new(StandardError)

    Result = Struct.new(:status, :meeting_document, :source, keyword_init: true) do
      def created?
        status == "created"
      end

      def reused?
        status == "reused"
      end
    end

    def initialize(meeting:, youtube_url:, srt_file:)
      @meeting = meeting
      @youtube_url = youtube_url
      @srt_file = srt_file
    end

    def import
      raise ImportError, "Uploaded SRT file is missing" unless @srt_file&.attached?

      @meeting.with_lock do
        srt_content = @srt_file.download
        plain_text = TranscriptDownloader.parse_srt(srt_content)
        raise ImportError, "Uploaded SRT did not contain transcript text" if plain_text.blank?

        @meeting.meeting_documents.where(document_type: "transcript").destroy_all

        document = @meeting.meeting_documents.create!(
          document_type: "transcript",
          source_url: @youtube_url,
          extracted_text: plain_text,
          text_quality: "uploaded_transcript",
          text_chars: plain_text.length,
          fetched_at: Time.current
        )

        begin
          attach_transcript_file(document, srt_content)
        rescue StandardError
          document.destroy!
          raise
        end

        Result.new(status: "created", meeting_document: document, source: "uploaded_srt")
      end
    end

    private

    def attach_transcript_file(document, srt_content)
      document.file.attach(
        io: StringIO.new(srt_content),
        filename: @srt_file.filename.to_s.presence || "uploaded-transcript-#{@meeting.id}.srt",
        content_type: "text/srt"
      )
    end
  end
end
