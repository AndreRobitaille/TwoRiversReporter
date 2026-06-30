module Admin
  class TranscriptImportWorkflowJob < ApplicationJob
    queue_as :default

    def perform(transcript_import_id)
      transcript_import = TranscriptImport.find(transcript_import_id)
      run_workflow(transcript_import)
    rescue StandardError => e
      current_step = @current_step || "workflow"
      log_failure(transcript_import_id, transcript_import, e, current_step)
      raise unless transcript_import&.persisted?

      transcript_import.mark_failed!(e, step: current_step)
    end

    private

    def run_workflow(transcript_import)
      @current_step = "workflow"
      transcript_import.mark_running!
      log_and_append(transcript_import, step: "workflow", message: "Transcript import workflow started")

      @current_step = "download_transcript"
      downloader_result = Documents::TranscriptDownloader
        .new(meeting: transcript_import.meeting, video_url: transcript_import.youtube_url)
        .download_and_store

      meeting_document = downloader_result.meeting_document
      log_and_append(transcript_import,
        step: "download_transcript",
        message: downloader_result.reused? ? "Transcript reused" : "Transcript downloaded",
        metadata: {
          status: downloader_result.status,
          meeting_document_id: meeting_document&.id,
          text_chars: meeting_document&.text_chars
        }
      )

      log_and_append(transcript_import, step: "summarize_meeting", message: "SummarizeMeetingJob started")
      @current_step = "summarize_meeting"
      SummarizeMeetingJob.perform_now(transcript_import.meeting_id, enqueue_followups: false)
      log_and_append(transcript_import, step: "summarize_meeting", message: "SummarizeMeetingJob finished")

      log_and_append(transcript_import, step: "prune_hollow_appearances", message: "PruneHollowAppearancesJob started")
      @current_step = "prune_hollow_appearances"
      PruneHollowAppearancesJob.perform_now(transcript_import.meeting_id)
      log_and_append(transcript_import, step: "prune_hollow_appearances", message: "PruneHollowAppearancesJob finished")

      log_and_append(transcript_import, step: "reanalyze_topics", message: "Meeting reanalysis started")
      @current_step = "reanalyze_topics"
      reanalysis_result = ::Topics::MeetingReanalysisService.new(transcript_import.meeting_id).call
      log_and_append(transcript_import,
        step: "reanalyze_topics",
        message: "Meeting reanalysis finished",
        metadata: {
          before_topic_ids: reanalysis_result.before_topic_ids,
          after_topic_ids: reanalysis_result.after_topic_ids,
          affected_topic_ids: reanalysis_result.affected_topic_ids
        }
      )

      transcript_import.mark_completed!(
        meeting_document: meeting_document,
        affected_topic_ids: reanalysis_result.affected_topic_ids
      )
      log_and_append(transcript_import,
        step: "workflow",
        message: "Transcript import workflow completed",
        metadata: {
          meeting_document_id: meeting_document&.id,
          affected_topic_ids: reanalysis_result.affected_topic_ids
        }
      )
    end

    def log_failure(transcript_import_id, transcript_import, error, current_step)
      Rails.logger.error(
        "TranscriptImportWorkflowJob failed step=#{current_step} transcript_import_id=#{transcript_import_id} " \
        "meeting_id=#{transcript_import&.meeting_id} youtube_url=#{transcript_import&.youtube_url} " \
        "error_class=#{error.class.name} error_message=#{error.message}"
      )
    end

    def log_and_append(transcript_import, step:, message:, metadata: {})
      Rails.logger.info(
        "TranscriptImportWorkflowJob step=#{step} transcript_import_id=#{transcript_import.id} " \
        "meeting_id=#{transcript_import.meeting_id} message=#{message}"
      )
      transcript_import.append_step_log!(step: step, message: message, metadata: metadata)
    end
  end
end
