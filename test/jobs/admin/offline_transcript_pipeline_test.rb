require "test_helper"
require_relative "../../support/offline_transcript_pipeline"

module Admin
  class OfflineTranscriptPipelineTest < ActiveJob::TestCase
    include OfflineTranscriptPipeline

    setup do
      build_pipeline_fixture
      @import = TranscriptImport.create!(meeting: @meeting, status: "queued", youtube_url: "https://www.youtube.com/watch?v=OfflineFixture")
      @import.srt_file.attach(io: StringIO.new(@srt), filename: "offline.srt", content_type: "text/srt")
    end

    test "real uploaded transcript stages retain both identities source versions and closing evidence on rerun" do
      run_pipeline
      assert_complete_state
      first_document = @import.reload.meeting_document
      stable_ids = persistent_ids
      history = @import.dup
      history.save!
      history.srt_file.attach(@import.srt_file.blob)
      history_state = history.reload.attributes.except("meeting_document_id")
      first_appearance_state = TopicAppearance.where(meeting: @meeting).order(:id).map(&:attributes)

      @boundaries.clear
      run_pipeline
      assert_complete_state
      assert_not MeetingDocument.exists?(first_document.id), "rerun replaces the uploaded artifact, not topic identities"
      assert_not_equal first_document.id, @import.reload.meeting_document_id
      assert_nil history.reload.meeting_document_id
      assert_equal history_state, history.attributes.except("meeting_document_id")
      assert_equal @srt.b, history.srt_file.download.b
      assert_equal stable_ids, persistent_ids
      assert_equal first_appearance_state, TopicAppearance.where(meeting: @meeting).order(:id).map(&:attributes)
      assert_equal [ @import.meeting_document_id ], @meeting.meeting_documents.where(document_type: "transcript").pluck(:id)
    end

    test "mid extraction failure removes partial new identities and restores old links before a usable retry" do
      replacement = Topic.create!(name: "harbor lighting", status: "approved", review_status: "approved")
      @broken_replacement = replacement
      before_pairs = link_pairs
      before_appearances = TopicAppearance.where(meeting: @meeting).order(:id).map(&:attributes)

      run_pipeline
      assert_equal "failed", @import.reload.status
      assert_equal "NoMethodError", @import.error_class
      assert_equal "reanalyze_topics", @import.step_logs.last.fetch("step")
      continuity_args = enqueued_jobs.select { |job| job[:job] == ::Topics::UpdateContinuityJob }.flat_map do |job|
        ActiveJob::Arguments.deserialize(job.fetch(:args))
      end
      assert continuity_args.any? { |args| args[:topic_id] == replacement.id }, "real partial creation must have queued its continuity callback"
      assert_equal before_pairs, link_pairs
      assert_equal before_appearances, TopicAppearance.where(meeting: @meeting).order(:id).map(&:attributes)
      assert_not TopicAppearance.exists?(meeting: @meeting, topic: replacement)
      assert_not AgendaItemTopic.exists?(topic: replacement, agenda_item: @items)
      assert_equal @topics.map(&:id).sort, @meeting.topic_summaries.pluck(:topic_id).sort
      assert_official_state
      assert_uploaded_source(@meeting.latest_document("transcript"))

      @broken_replacement = nil
      @boundaries.clear
      run_pipeline
      assert_complete_state
      assert_nil @import.reload.error_class
      assert_not TopicAppearance.exists?(meeting: @meeting, topic: replacement)
    end
  end
end
