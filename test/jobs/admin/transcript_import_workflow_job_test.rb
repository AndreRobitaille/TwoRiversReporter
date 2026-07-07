require "test_helper"
require "minitest/mock"

module Admin
  class TranscriptImportWorkflowJobTest < ActiveJob::TestCase
    setup do
      @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago, detail_page_url: "http://example.com/meeting-#{SecureRandom.hex(4)}")
      @transcript_import = TranscriptImport.create!(meeting: @meeting, youtube_url: "https://www.youtube.com/watch?v=abc123", status: "queued")
    end

    test "successfully downloads transcript, summarizes, prunes, reanalyzes, and completes" do
      document = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @transcript_import.youtube_url, extracted_text: "Transcript text", text_quality: "auto_transcribed", text_chars: 15)
      download_result = Documents::TranscriptDownloader::Result.new(status: "created", meeting_document: document)

      downloader = Minitest::Mock.new
      downloader.expect :download_and_store, download_result

      reanalysis_result = ::Topics::MeetingReanalysisService::Result.new(meeting: @meeting, before_topic_ids: [ 2, 1 ], after_topic_ids: [ 3, 2 ], affected_topic_ids: [ 1, 2, 3 ], selector_ids: [], wire_ids: [])
      reanalysis_service = Minitest::Mock.new
      reanalysis_service.expect :call, reanalysis_result

      events = []

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, ->(meeting:, video_url:) {
          assert_equal @meeting, meeting
          assert_equal @transcript_import.youtube_url, video_url
          downloader
        } do
          SummarizeMeetingJob.stub :perform_now, ->(meeting_id, mode: :full, enqueue_followups: true) {
            events << :summarize
            assert_equal @meeting.id, meeting_id
            assert_equal :full, mode
            assert_equal false, enqueue_followups
          } do
            PruneHollowAppearancesJob.stub :perform_now, ->(meeting_id) {
              events << :prune
              assert_equal @meeting.id, meeting_id
            } do
              ::Topics::MeetingReanalysisService.stub :new, ->(meeting_id) {
                assert_equal @meeting.id, meeting_id
                events << :reanalyze
                reanalysis_service
              } do
                Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
              end
            end
          end
        end
      end

      downloader.verify
      reanalysis_service.verify

      assert_equal [ :summarize, :prune, :reanalyze ], events

      @transcript_import.reload
      assert_equal "completed", @transcript_import.status
      assert_equal document.id, @transcript_import.meeting_document_id
      assert_equal [ 1, 2, 3 ], @transcript_import.affected_topic_ids
      step_names = @transcript_import.step_logs.map { |entry| entry["step"] }
      assert_operator step_names.index("prune_hollow_appearances"), :<, step_names.index("reanalyze_topics")
      assert_operator step_names.index("summarize_meeting"), :<, step_names.index("prune_hollow_appearances")

      download_log = @transcript_import.step_logs.find { |entry| entry["step"] == "download_transcript" }
      assert_equal "created", download_log.dig("metadata", "status")
      assert_equal "youtube_captions", download_log.dig("metadata", "source")
      assert_equal "Transcript downloaded", download_log["message"]
      assert_equal document.id, download_log.dig("metadata", "meeting_document_id")
      assert_equal 15, download_log.dig("metadata", "text_chars")

      reanalysis_start = @transcript_import.step_logs.find { |entry| entry["step"] == "reanalyze_topics" && entry["message"] == "Meeting reanalysis started" }
      reanalysis_finish = @transcript_import.step_logs.find { |entry| entry["step"] == "reanalyze_topics" && entry["message"] == "Meeting reanalysis finished" }
      assert reanalysis_start
      assert_equal [ 1, 2, 3 ], reanalysis_finish.dig("metadata", "affected_topic_ids")
      assert_equal [ 2, 1 ], reanalysis_finish.dig("metadata", "before_topic_ids")
      assert_equal [ 3, 2 ], reanalysis_finish.dig("metadata", "after_topic_ids")
    end

    test "uses uploaded srt importer when an srt file is attached" do
      @transcript_import.srt_file.attach(
        io: StringIO.new("1\n00:00:01,000 --> 00:00:03,000\nUploaded transcript text."),
        filename: "manual.srt",
        content_type: "text/srt"
      )
      document = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @transcript_import.youtube_url, extracted_text: "Uploaded transcript text.", text_quality: "uploaded_transcript", text_chars: 25)
      upload_result = Documents::UploadedTranscriptImporter::Result.new(status: "created", meeting_document: document, source: "uploaded_srt")

      importer = Minitest::Mock.new
      importer.expect :import, upload_result

      reanalysis_result = ::Topics::MeetingReanalysisService::Result.new(meeting: @meeting, before_topic_ids: [], after_topic_ids: [], affected_topic_ids: [], selector_ids: [], wire_ids: [])
      reanalysis_service = Minitest::Mock.new
      reanalysis_service.expect :call, reanalysis_result

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, ->(*) { flunk "should not use YouTube downloader when an SRT is uploaded" } do
          Documents::UploadedTranscriptImporter.stub :new, ->(meeting:, youtube_url:, srt_file:) {
            assert_equal @meeting, meeting
            assert_equal @transcript_import.youtube_url, youtube_url
            assert srt_file.attached?
            assert_equal "manual.srt", srt_file.blob.filename.to_s
            importer
          } do
            SummarizeMeetingJob.stub :perform_now, ->(meeting_id, mode: :full, enqueue_followups: true) {
              assert_equal @meeting.id, meeting_id
              assert_equal :full, mode
              assert_equal false, enqueue_followups
            } do
              PruneHollowAppearancesJob.stub :perform_now, ->(meeting_id) { assert_equal @meeting.id, meeting_id } do
                ::Topics::MeetingReanalysisService.stub :new, ->(meeting_id) {
                  assert_equal @meeting.id, meeting_id
                  reanalysis_service
                } do
                  Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
                end
              end
            end
          end
        end
      end

      importer.verify
      reanalysis_service.verify

      @transcript_import.reload
      assert_equal "completed", @transcript_import.status
      assert_equal document.id, @transcript_import.meeting_document_id

      import_log = @transcript_import.step_logs.find { |entry| entry["step"] == "download_transcript" }
      assert_equal "Transcript uploaded", import_log["message"]
      assert_equal "created", import_log.dig("metadata", "status")
      assert_equal "uploaded_srt", import_log.dig("metadata", "source")
      assert_equal document.id, import_log.dig("metadata", "meeting_document_id")
    end

    test "logs reused transcript and still completes" do
      reused_document = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @transcript_import.youtube_url, extracted_text: "Existing transcript", text_quality: "auto_transcribed", text_chars: 19)
      download_result = Documents::TranscriptDownloader::Result.new(status: "reused", meeting_document: reused_document)

      downloader = Minitest::Mock.new
      downloader.expect :download_and_store, download_result

      reanalysis_result = ::Topics::MeetingReanalysisService::Result.new(meeting: @meeting, before_topic_ids: [], after_topic_ids: [], affected_topic_ids: [], selector_ids: [], wire_ids: [])
      reanalysis_service = Minitest::Mock.new
      reanalysis_service.expect :call, reanalysis_result

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, ->(meeting:, video_url:) {
          assert_equal @meeting, meeting
          assert_equal @transcript_import.youtube_url, video_url
          downloader
        } do
          SummarizeMeetingJob.stub :perform_now, ->(meeting_id, mode: :full, enqueue_followups: true) {
            assert_equal @meeting.id, meeting_id
            assert_equal :full, mode
            assert_equal false, enqueue_followups
          } do
            PruneHollowAppearancesJob.stub :perform_now, ->(meeting_id) { assert_equal @meeting.id, meeting_id } do
              ::Topics::MeetingReanalysisService.stub :new, ->(meeting_id) {
                assert_equal @meeting.id, meeting_id
                reanalysis_service
              } do
                Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
              end
            end
          end
        end
      end

      downloader.verify
      reanalysis_service.verify

      @transcript_import.reload
      assert_equal "completed", @transcript_import.status
      assert_equal reused_document.id, @transcript_import.meeting_document_id
      download_log = @transcript_import.step_logs.find { |entry| entry["step"] == "download_transcript" }
      assert_equal "reused", download_log.dig("metadata", "status")
      assert_equal "youtube_captions", download_log.dig("metadata", "source")
      assert_equal "Transcript reused", download_log["message"]
    end

    test "logs reused uploaded transcript provenance without calling it uploaded during workflow" do
      reused_document = MeetingDocument.create!(meeting: @meeting, document_type: "transcript", source_url: @transcript_import.youtube_url, extracted_text: "Existing uploaded transcript", text_quality: "uploaded_transcript", text_chars: 28)
      reused_document.file.attach(io: StringIO.new("srt"), filename: "existing.srt", content_type: "text/srt")
      download_result = Documents::TranscriptDownloader::Result.new(status: "reused", meeting_document: reused_document, source: "uploaded_srt")

      downloader = Minitest::Mock.new
      downloader.expect :download_and_store, download_result

      reanalysis_result = ::Topics::MeetingReanalysisService::Result.new(meeting: @meeting, before_topic_ids: [], after_topic_ids: [], affected_topic_ids: [], selector_ids: [], wire_ids: [])
      reanalysis_service = Minitest::Mock.new
      reanalysis_service.expect :call, reanalysis_result

      Rails.logger.stub :error, nil do
        Documents::TranscriptDownloader.stub :new, ->(meeting:, video_url:) {
          assert_equal @meeting, meeting
          assert_equal @transcript_import.youtube_url, video_url
          downloader
        } do
          SummarizeMeetingJob.stub :perform_now, ->(meeting_id, mode: :full, enqueue_followups: true) {
            assert_equal @meeting.id, meeting_id
            assert_equal :full, mode
            assert_equal false, enqueue_followups
          } do
            PruneHollowAppearancesJob.stub :perform_now, ->(meeting_id) { assert_equal @meeting.id, meeting_id } do
              ::Topics::MeetingReanalysisService.stub :new, ->(meeting_id) {
                assert_equal @meeting.id, meeting_id
                reanalysis_service
              } do
                Admin::TranscriptImportWorkflowJob.perform_now(@transcript_import.id)
              end
            end
          end
        end
      end

      downloader.verify
      reanalysis_service.verify

      @transcript_import.reload
      assert_equal "completed", @transcript_import.status
      download_log = @transcript_import.step_logs.find { |entry| entry["step"] == "download_transcript" }
      assert_equal "reused", download_log.dig("metadata", "status")
      assert_equal "uploaded_srt", download_log.dig("metadata", "source")
      assert_equal "Transcript reused", download_log["message"]
    end

    test "stores failure details and logs the failing substep" do
      downloader = Object.new
      downloader.define_singleton_method(:download_and_store) { raise StandardError, "boom" }

      logged_message = nil
      Rails.logger.stub :error, ->(message) { logged_message = message } do
        Documents::TranscriptDownloader.stub :new, ->(meeting:, video_url:) {
          assert_equal @meeting, meeting
          assert_equal @transcript_import.youtube_url, video_url
          downloader
        } do
          assert_nothing_raised do
            Admin::TranscriptImportWorkflowJob.new.perform(@transcript_import.id)
          end
        end
      end

      @transcript_import.reload
      assert_equal "failed", @transcript_import.status
      assert_equal "StandardError", @transcript_import.error_class
      assert_equal "boom", @transcript_import.error_message
      assert_includes logged_message, "transcript_import_id=#{@transcript_import.id}"
      assert_includes logged_message, "meeting_id=#{@meeting.id}"
      assert_includes logged_message, "youtube_url=#{@transcript_import.youtube_url}"
      assert_includes logged_message, "error_class=StandardError"
      assert_includes logged_message, "error_message=boom"
      assert_includes logged_message, "step=download_transcript"
      assert_equal "download_transcript", @transcript_import.step_logs.last["step"]
    end

    test "re-raises when transcript import id does not exist" do
      logged_message = nil
      Rails.logger.stub :error, ->(message) { logged_message = message } do
        assert_raises(ActiveRecord::RecordNotFound) do
          Admin::TranscriptImportWorkflowJob.new.perform(-1)
        end
      end

      assert_includes logged_message, "transcript_import_id=-1"
      assert_includes logged_message, "error_class=ActiveRecord::RecordNotFound"
    end
  end
end
