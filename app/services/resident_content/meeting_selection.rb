module ResidentContent
  class MeetingSelection
    def self.catalog
      records = Meeting.includes(:committee).to_a
      [ MeetingDocument, MeetingSummary ].each do |model|
        association = model == MeetingDocument ? :meeting_documents : :meeting_summaries
        ActiveRecord::Associations::Preloader.new(records: records, associations: association,
          scope: model.select(:id, :meeting_id)).call
      end
      canonical(records)
    end

    def self.canonical(meetings)
      meetings.group_by(&:duplicate_identity_key).values.map { |group| Meeting.preferred_duplicate(group) }
    end

    def self.preferred_summary(meeting)
      return if meeting.cancelled?

      meeting.meeting_summaries.select { |summary| summary.content.present? || summary.generation_data.present? }
        .min_by { |summary| [ MeetingSummary::SUMMARY_TYPES.index(summary.summary_type) || 99,
          -(summary.updated_at || summary.created_at || Time.at(0)).to_r, summary.id ] }
    end
  end
end
