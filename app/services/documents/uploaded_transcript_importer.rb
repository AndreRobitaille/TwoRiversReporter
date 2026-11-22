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

      @meeting.with_lock("FOR NO KEY UPDATE") do
        srt_content = @srt_file.download.force_encoding(Encoding::UTF_8)
        plain_text = TranscriptDownloader.parse_srt(srt_content)
        raise ImportError, "Uploaded SRT did not contain transcript text" if plain_text.blank?

        documents = @meeting.meeting_documents.where(document_type: "transcript").to_a
        existing = documents.first if documents.one?
        if existing&.source_url == @youtube_url && existing.text_quality == "uploaded_transcript" &&
            existing.extracted_text == plain_text && existing.file.attached? &&
            existing.file.blob.checksum == @srt_file.blob.checksum
          return Result.new(status: "reused", meeting_document: existing, source: "uploaded_srt")
        end
        documents.each(&:destroy!)

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
