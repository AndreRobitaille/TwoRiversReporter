module Scrapers
  class PipelineRepairSweep
    LOOKBACK_WINDOW = 90.days

    def initialize(discovered_meeting_ids = [], since: nil)
      @discovered_meeting_ids = Array(discovered_meeting_ids).compact
      @since = since || LOOKBACK_WINDOW.ago
    end

    def call
      meetings = scoped_meetings
      counters = {
        meetings_scoped: meetings.size,
        parse_meeting_pages_enqueued: 0,
        document_downloads_enqueued: 0,
        agenda_parses_enqueued: 0,
        summaries_enqueued: 0,
        topic_extractions_enqueued: 0,
        vote_extractions_enqueued: 0,
        committee_member_extractions_enqueued: 0
      }

      meetings.find_each do |meeting|
        unless meeting.meeting_page_parsed? || discovered_meeting_ids.include?(meeting.id)
          Scrapers::ParseMeetingPageJob.perform_later(meeting.id)
          counters[:parse_meeting_pages_enqueued] += 1
        end

        repair_documents(meeting, counters)
        repair_agenda(meeting, counters)
        repair_extractions(meeting, counters)
        repair_summary(meeting, counters)
      end

      counters
    end

    private

    attr_reader :discovered_meeting_ids, :since

    def scoped_meetings
      Meeting.where(id: discovered_meeting_ids).or(Meeting.where(starts_at: since..Time.current)).distinct
    end

    def repair_documents(meeting, counters)
      meeting.meeting_documents.find_each do |document|
        if pdf_analysis_needed?(document)
          Documents::AnalyzePdfJob.perform_later(document.id)
          counters[:document_downloads_enqueued] += 1
          next
        end

        next if document.fetched_at.present? && document.file.attached?

        Documents::DownloadJob.perform_later(document.id)
        counters[:document_downloads_enqueued] += 1
      end
    end

    def repair_agenda(meeting, counters)
      return unless Scrapers::ParseAgendaJob.meeting_has_usable_agenda_source?(meeting)
      return if meeting.processing_state.stringify_keys["agenda_checked_at"].present?
      return if meeting.agenda_structure_digest.present?

      if agenda_repair_already_satisfied?(meeting)
        meeting.mark_processing!(:agenda_checked_at)
        return
      end

      Scrapers::ParseAgendaJob.perform_later(meeting.id)
      counters[:agenda_parses_enqueued] += 1
    end

    def agenda_repair_already_satisfied?(meeting)
      meeting.agenda_items.exists? || meeting.meeting_summaries.any? { |summary| usable_meeting_summary?(summary) }
    end

    def usable_meeting_summary?(summary)
      summary.content.present? || summary.generation_data.present?
    end

    def repair_summary(meeting, counters)
      return unless SummarizeMeetingJob.summary_repair_needed?(meeting)
      return unless extraction_complete_for_summary?(meeting)

      SummarizeMeetingJob.perform_later(meeting.id)
      counters[:summaries_enqueued] += 1
    end

    def repair_extractions(meeting, counters)
      enqueue_if_needed(meeting, counters, :topics_extracted_at, ExtractTopicsJob, :topic_extractions_enqueued) if meeting.agenda_items.substantive.exists?
      enqueue_if_needed(meeting, counters, :votes_extracted_at, ExtractVotesJob, :vote_extractions_enqueued) if meeting.meeting_documents.where(document_type: "minutes_pdf").where.not(extracted_text: [ nil, "" ]).exists?
      enqueue_if_needed(meeting, counters, :committee_members_extracted_at, ExtractCommitteeMembersJob, :committee_member_extractions_enqueued) if meeting.meeting_documents.where(document_type: "minutes_pdf").where.not(extracted_text: [ nil, "" ]).exists?
    end

    def enqueue_if_needed(meeting, counters, marker, job_class, counter_key)
      state = meeting.processing_state.stringify_keys
      status = extraction_status_key(marker).then { |key| state[key] }
      return if state.key?(marker.to_s) && status.present? && !retryable_marker_status?(status)

      job_class.perform_later(meeting.id)
      counters[counter_key] += 1
    end

    def terminal_marker_status?(status)
      %w[empty processed].include?(status)
    end

    def retryable_marker_status?(status)
      %w[parse_error missing_source].include?(status)
    end

    def pdf_analysis_needed?(document)
      return false unless document.file.attached?
      return false unless document.document_type.to_s.end_with?("pdf")

      document.extracted_text.blank? || document.page_count.blank? || document.text_quality.blank?
    end

    def extraction_complete_for_summary?(meeting)
      state = meeting.processing_state.stringify_keys
      source_type, = SummarizeMeetingJob.summary_target_for(meeting)
      required_markers = required_summary_markers(meeting, source_type)

      required_markers.all? do |marker|
        state.key?(marker.to_s) && terminal_marker_status?(state[extraction_status_key(marker)])
      end

    end

    def required_summary_markers(meeting, source_type)
      case source_type
      when "minutes_pdf"
        markers = [ :votes_extracted_at, :committee_members_extracted_at ]
        markers.unshift(:topics_extracted_at) if meeting.agenda_items.substantive.exists?
        markers
      when "transcript"
        meeting.agenda_items.substantive.exists? ? [ :topics_extracted_at ] : []
      when "packet_pdf"
        meeting.agenda_items.substantive.exists? ? [ :topics_extracted_at ] : []
      else
        []
      end
    end

    def extraction_status_key(marker)
      case marker.to_s
      when "topics_extracted_at" then "topics_extraction_status"
      when "votes_extracted_at" then "votes_extraction_status"
      when "committee_members_extracted_at" then "committee_members_extraction_status"
      end
    end
  end
end
