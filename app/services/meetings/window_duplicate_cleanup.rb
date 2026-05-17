module Meetings
  class WindowDuplicateCleanup
    CLEANUP_WINDOW = 21.days

    USEFUL_ASSOCIATIONS = %i[
      meeting_documents
      agenda_items
      meeting_summaries
      topic_summaries
      motions
      meeting_attendances
      knowledge_sources
    ].freeze

    def self.call(dry_run: true)
      new(dry_run: dry_run).call
    end

    def initialize(dry_run: true)
      @dry_run = dry_run
      @report = { kept_ids: [], deleted_ids: [], skipped_groups: [] }
    end

    def call
      duplicate_groups.each { |meetings| clean_group(meetings) }
      report
    end

    private

    attr_reader :dry_run, :report

    def duplicate_groups
      Meeting.where(starts_at: CLEANUP_WINDOW.ago..CLEANUP_WINDOW.from_now)
        .includes(*USEFUL_ASSOCIATIONS)
        .group_by(&:duplicate_identity_key)
        .values
        .select { |meetings| meetings.size > 1 }
    end

    def clean_group(meetings)
      keeper = useful_record_keeper(meetings) || cancelled_empty_keeper(meetings)
      return skip_group(meetings) unless keeper

      deletion_candidates = meetings - [ keeper ]
      return skip_group(meetings) unless deletion_candidates.all? { |meeting| empty_duplicate?(meeting) }

      report[:kept_ids] << keeper.id
      deletion_candidates.each { |meeting| delete_meeting(meeting) }
    end

    def useful_record_keeper(meetings)
      useful_records = meetings.reject { |meeting| empty_duplicate?(meeting) }
      useful_records.first if useful_records.one?
    end

    def cancelled_empty_keeper(meetings)
      return unless meetings.all? { |meeting| empty_duplicate?(meeting) }

      cancelled_records = meetings.select { |meeting| cancelled_meeting?(meeting) }
      cancelled_records.first if cancelled_records.one?
    end

    def empty_duplicate?(meeting)
      USEFUL_ASSOCIATIONS.all? { |association| meeting.public_send(association).empty? }
    end

    def cancelled_meeting?(meeting)
      meeting.body_name.to_s.match?(/\b(cancelled|canceled)\b/i)
    end

    def delete_meeting(meeting)
      report[:deleted_ids] << meeting.id
      meeting.destroy! unless dry_run
    end

    def skip_group(meetings)
      report[:skipped_groups] << meetings.map(&:id).sort
    end
  end
end
