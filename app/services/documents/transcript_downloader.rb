require "json"
require "net/http"
require "open3"
require "timeout"

module Documents
  class TranscriptDownloader
    YOUTUBE_URL_PATTERN = %r{\Ahttps://www\.youtube\.com/watch\?v=[A-Za-z0-9_-]+\z}
    YT_DLP_TIMEOUT = 30.seconds
    YT_DLP_BASE_ARGS = [ "yt-dlp", "--no-update", "--js-runtimes", "deno" ].freeze
    YOUTUBE_COOKIES_PATH = "/rails/storage/youtube.cookies.txt"
    APIFY_TRANSCRIPTS_ENDPOINT = URI("https://api.apify.com/v2/acts/johnvc~YoutubeTranscripts/run-sync-get-dataset-items")
    APIFY_TIMEOUT = 180.seconds

    InvalidUrlError = Class.new(StandardError)
    DownloadError = Class.new(StandardError)

    Result = Struct.new(:status, :meeting_document, :source, keyword_init: true) do
      def created?
        status == "created"
      end

      def reused?
        status == "reused"
      end
    end

    PrecheckResult = Struct.new(:status, :message, :details, keyword_init: true)

    def self.valid_url?(video_url)
      video_url.match?(YOUTUBE_URL_PATTERN)
    end

    def self.precheck(video_url)
      unless valid_url?(video_url)
        return PrecheckResult.new(status: :invalid_url, message: "URL must be a youtube.com watch URL", details: nil)
      end

      stdout, stderr, status = run_yt_dlp(*yt_dlp_args, "--dump-single-json", "--skip-download", video_url)
      unless status.success?
        details = stderr.to_s.strip.presence || stdout.to_s.strip.presence
        return PrecheckResult.new(
          status: :verification_unavailable,
          message: "Server could not verify captions availability, likely due to YouTube blocking or rate limiting",
          details: details
        )
      end

      metadata = JSON.parse(stdout)
      subtitles = metadata.fetch("subtitles", {})
      automatic_captions = metadata.fetch("automatic_captions", {})

      if subtitles.fetch("en", []).any? || automatic_captions.fetch("en", []).any?
        PrecheckResult.new(status: :captions_available, message: "English captions appear to be available", details: nil)
      else
        PrecheckResult.new(status: :captions_missing, message: "No English captions were found", details: nil)
      end
    rescue JSON::ParserError => e
      PrecheckResult.new(
        status: :verification_unavailable,
        message: "Server could not read unreadable metadata to verify captions availability",
        details: e.message
      )
    rescue DownloadError => e
      PrecheckResult.new(status: :verification_unavailable, message: e.message, details: e.message)
    end

    def self.parse_srt(srt_content)
      srt_content
        .to_s
        .gsub(/^\d+\s*$/, "")
        .gsub(/^\d{2}:\d{2}:\d{2},\d{3}\s*-->.*$/, "")
        .gsub(/\n{3,}/, "\n\n")
        .strip
    end

    def self.run_yt_dlp(*args)
      Timeout.timeout(YT_DLP_TIMEOUT) { Open3.capture3(*args) }
    rescue Timeout::Error => e
      raise DownloadError, "yt-dlp timed out after #{YT_DLP_TIMEOUT} while verifying captions: #{e.message}"
    rescue Errno::ENOENT, Errno::EACCES, IOError, SystemCallError => e
      raise DownloadError, "yt-dlp could not be executed: #{e.message}"
    end

    def self.yt_dlp_args
      return YT_DLP_BASE_ARGS unless File.exist?(YOUTUBE_COOKIES_PATH)

      YT_DLP_BASE_ARGS + [ "--cookies", YOUTUBE_COOKIES_PATH ]
    end

    # Optional fallback for when YouTube blocks yt-dlp on the server (#87).
    # Credentials first, ENV as the escape hatch, like the other API keys.
    def self.apify_token
      Rails.application.credentials.apify_token || ENV["APIFY_TOKEN"].presence
    end

    def initialize(meeting:, video_url:)
      @meeting = meeting
      @video_url = video_url
    end

    def download_and_store
      raise InvalidUrlError, "Invalid YouTube URL" unless self.class.valid_url?(@video_url)

      @meeting.with_lock do
        existing_document = @meeting.meeting_documents.find_by(document_type: "transcript")
        if existing_document&.file&.attached? && existing_document.extracted_text.present?
          return Result.new(
            status: "reused",
            meeting_document: existing_document,
            source: existing_document.text_quality == "uploaded_transcript" ? "uploaded_srt" : "youtube_captions"
          )
        end

        existing_document&.destroy!

        srt_content, plain_text, text_quality = download_captions
        raise DownloadError, "yt-dlp did not produce transcript text" if plain_text.blank?

        document = @meeting.meeting_documents.create!(
          document_type: "transcript",
          source_url: @video_url,
          extracted_text: plain_text,
          text_quality: text_quality,
          text_chars: plain_text.length,
          fetched_at: Time.current
        )

        begin
          attach_transcript_file(document, srt_content)
        rescue StandardError
          document.destroy!
          raise
        end

        Result.new(status: "created", meeting_document: document, source: "youtube_captions")
      end
    end

    private

    def download_captions
      download_yt_dlp_captions
    rescue DownloadError => e
      raise if self.class.apify_token.blank?

      download_apify_captions || raise(e)
    end

    def download_yt_dlp_captions
      Dir.mktmpdir("transcript") do |tmpdir|
        [
          [ "--write-sub", "manual_caption" ],
          [ "--write-auto-sub", "auto_transcribed" ]
        ].each do |caption_flag, text_quality|
          srt_content, plain_text = download_captions_for(tmpdir, caption_flag)
          next if plain_text.blank?

          return [ srt_content, plain_text, text_quality ]
        end

        raise DownloadError, "yt-dlp produced no SRT file"
      end
    end

    def download_captions_for(tmpdir, caption_flag)
      stdout, stderr, status = self.class.run_yt_dlp(
        *self.class.yt_dlp_args,
        caption_flag,
        "--sub-lang", "en",
        "--sub-format", "srt",
        "--skip-download",
        "-o", "#{tmpdir}/video",
        @video_url
      )

      unless status.success?
        raise DownloadError, "yt-dlp failed to download transcript captions: #{stderr.to_s.strip.presence || stdout.to_s.strip}"
      end

      srt_files = Dir.glob("#{tmpdir}/*.srt")
      return [ nil, nil ] if srt_files.empty?

      srt_content = File.read(srt_files.first)
      plain_text = parse_srt(srt_content)
      [ srt_content, plain_text ]
    end

    def download_apify_captions
      request = Net::HTTP::Post.new(APIFY_TRANSCRIPTS_ENDPOINT)
      request["Authorization"] = "Bearer #{self.class.apify_token}"
      request["Content-Type"] = "application/json"
      request.body = { youtube_url: @video_url, languages: [ "en" ], include_metadata: false }.to_json

      response = Net::HTTP.start(
        APIFY_TRANSCRIPTS_ENDPOINT.host,
        APIFY_TRANSCRIPTS_ENDPOINT.port,
        use_ssl: true,
        open_timeout: 10,
        read_timeout: APIFY_TIMEOUT.to_i
      ) { |http| http.request(request) }

      unless response.is_a?(Net::HTTPSuccess)
        Rails.logger.warn "TranscriptDownloader: Apify transcript fallback returned HTTP #{response.code}"
        return nil
      end

      srt_content = srt_from_apify_row(Array(JSON.parse(response.body)).first)
      plain_text = parse_srt(srt_content)
      return nil if plain_text.blank?

      [ srt_content, plain_text, "auto_transcribed" ]
    rescue JSON::ParserError, Timeout::Error, SocketError, IOError, SystemCallError, OpenSSL::SSL::SSLError, Net::HTTPBadResponse, Net::ProtocolError => e
      Rails.logger.warn "TranscriptDownloader: Apify transcript fallback failed: #{e.message}"
      nil
    end

    def srt_from_apify_row(row)
      return unless row.is_a?(Hash)
      return if row["error"].present? || row["error_message"].present? || row["success"] == false

      cues = Array(row["timestamped"]).select { |cue| cue.is_a?(Hash) && cue["text"].to_s.strip.present? }
      cues.each_with_index.map do |cue, index|
        start = cue["start"].to_f
        "#{index + 1}\n#{srt_timestamp(start)} --> #{srt_timestamp(start + cue["duration"].to_f)}\n#{cue["text"].to_s.strip}\n"
      end.join("\n").presence
    end

    def srt_timestamp(seconds)
      millis = (seconds * 1000).round
      format("%02d:%02d:%02d,%03d", millis / 3_600_000, millis / 60_000 % 60, millis / 1000 % 60, millis % 1000)
    end

    def parse_srt(srt_content)
      self.class.parse_srt(srt_content)
    end

    def attach_transcript_file(document, srt_content)
      document.file.attach(
        io: StringIO.new(srt_content),
        filename: "transcript-#{@meeting.starts_at.to_date}.srt",
        content_type: "text/srt"
      )
    end
  end
end
