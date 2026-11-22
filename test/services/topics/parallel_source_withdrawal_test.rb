require "test_helper"
require "timeout"
require_relative "../../support/briefing_withdrawal_scenario"

class Topics::ParallelSourceWithdrawalTest < ActiveJob::TestCase
  include BriefingWithdrawalScenario
  self.use_transactional_tests = false

  setup { build_withdrawal_scenario }
  teardown { clean_withdrawal_scenario }

  test "source publication waits for first briefing then withdraws its motion-only receipt" do
    @briefing.destroy!
    race_first_briefing(@topic) do
      URI.stub(:open, ->(*) { StringIO.new("Synthetic revised artifact") }) { Documents::DownloadJob.perform_now(@document.id) }
    end
    assert_nil @topic.reload.published_topic_briefing
    assert_equal CLAIM, @topic.topic_briefing.headline
    assert_not_nil @other.reload.published_topic_briefing
    assert_equal 2, @document.reload.source_versions.count
  end

  test "transcript replacement can commit after concurrent first briefing without a meeting foreign key deadlock" do
    video = "https://www.youtube.com/watch?v=synthetic"
    old = @meeting.meeting_documents.create!(document_type: "transcript", source_url: video, extracted_text: "Old synthetic transcript")
    @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: {
      source_catalog: [ Citations::SourceCatalog.snapshot(old) ], item_details: []
    })
    upload = TranscriptImport.create!(meeting: @meeting, youtube_url: video, status: "queued")
    upload.srt_file.attach(io: StringIO.new("1\n00:00:01,000 --> 00:00:03,000\nNew synthetic words\n"), filename: "synthetic.srt", content_type: "text/srt")
    @other_briefing.destroy!
    race_first_briefing(@other) do
      Documents::UploadedTranscriptImporter.new(meeting: Meeting.find(@meeting.id), youtube_url: video, srt_file: upload.srt_file).import
    end
    assert_nil @other.reload.published_topic_briefing
    assert_equal [ old.id ], @other.topic_briefing.generation_data.fetch("source_catalog").map { |source| source.fetch("document_id") }
    refute MeetingDocument.exists?(old.id)
    assert_equal "New synthetic words", @meeting.meeting_documents.where(document_type: "transcript").sole.extracted_text
  end

  test "identical uploaded transcript reuses document and supported briefing without provider calls" do
    video = "https://www.youtube.com/watch?v=synthetic"
    upload = TranscriptImport.create!(meeting: @meeting, youtube_url: video, status: "queued")
    upload.srt_file.attach(io: StringIO.new("1\n00:00:01,000 --> 00:00:03,000\nSynthetic transcript\n"), filename: "synthetic.srt", content_type: "text/srt")
    importer = Documents::UploadedTranscriptImporter.new(meeting: @meeting, youtube_url: video, srt_file: upload.srt_file)
    result = without_paid_providers { importer.import }
    assert_predicate result, :created?
    @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: {
      source_catalog: [ Citations::SourceCatalog.snapshot(result.meeting_document.reload) ], item_details: []
    })
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @other.id, meeting_id: @meeting.id) }
    retained = @other_briefing.reload.attributes
    without_paid_providers do
      reused = importer.import
      assert_predicate reused, :reused?
      assert_equal result.meeting_document.id, reused.meeting_document.id
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: @other.id, meeting_id: @meeting.id)
    end
    assert_equal retained, @other_briefing.reload.attributes
    assert_equal 1, @meeting.meeting_documents.where(document_type: "transcript").count
    assert_not_nil @other.reload.published_topic_briefing
  end

  test "failed transcript replacement preserves the committed source and its dependent briefing" do
    video = "https://www.youtube.com/watch?v=synthetic"
    old = @meeting.meeting_documents.create!(document_type: "transcript", source_url: video, extracted_text: "Old synthetic transcript")
    @meeting.meeting_summaries.create!(summary_type: "transcript_recap", generation_data: {
      source_catalog: [ Citations::SourceCatalog.snapshot(old) ], item_details: []
    })
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @other.id, meeting_id: @meeting.id) }
    upload = TranscriptImport.create!(meeting: @meeting, youtube_url: video, status: "queued")
    upload.srt_file.attach(io: StringIO.new("1\n00:00:01,000 --> 00:00:03,000\nNew words\n"), filename: "synthetic.srt", content_type: "text/srt")
    importer = Documents::UploadedTranscriptImporter.new(meeting: @meeting, youtube_url: video, srt_file: upload.srt_file)
    without_paid_providers do
      importer.stub(:attach_transcript_file, ->(*) { raise IOError, "Synthetic attachment failure" }) do
        assert_raises(IOError) { importer.import }
      end
    end
    assert_equal old.id, @meeting.meeting_documents.where(document_type: "transcript").sole.id
    assert_not_nil @other.reload.published_topic_briefing
    assert_nil @other_briefing.reload.evidence_withdrawn_at
    assert_empty AuditEvent.where(subject: @other_briefing, action: "topic_briefing.source_withdrawn")
  end

  private

  def race_first_briefing(topic, &writer)
    entered, release, started = Queue.new, Queue.new, Queue.new
    workers = []
    topic_id = topic.id
    callback = -> do
      if self.topic_id == topic_id
        entered << true
        release.pop
      end
    end
    TopicBriefing.set_callback(:create, :before, callback)
    withdrawal_providers do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          Topics::GenerateTopicBriefingJob.perform_now(topic_id: topic_id, meeting_id: @meeting.id)
        end
      end
      Timeout.timeout(10) { entered.pop }
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do |connection|
          started << connection.select_value("SELECT pg_backend_pid()")
          writer.call
        end
      end
      pid = Timeout.timeout(10) { started.pop }
      wait_type = nil
      Timeout.timeout(10) do
        while workers.last.alive?
          wait_type = ActiveRecord::Base.uncached do
            ActiveRecord::Base.connection.select_value("SELECT wait_event_type FROM pg_stat_activity WHERE pid = #{Integer(pid)}")
          end
          break if wait_type == "Lock"
          sleep 0.01
        end
      end
      assert_equal "Lock", wait_type, "Source publication must serialize with first briefing publication"
      release << true
      Timeout.timeout(10) { workers.each(&:value) }
    end
  ensure
    release << true if release
    workers&.each { |worker| worker.join(10) }
    TopicBriefing.skip_callback(:create, :before, callback) if callback
  end
end
