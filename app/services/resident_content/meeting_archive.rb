module ResidentContent
  class MeetingArchive
    def initialize(as_of: Time.current)
      @past_meetings = Meeting.where(starts_at: ..as_of)
    end

    def months
      @past_meetings.distinct.pluck(:starts_at).map { |time| time.to_date.beginning_of_month }.uniq.sort.reverse
    end

    def meetings_for(month)
      meetings = @past_meetings.where(starts_at: month.in_time_zone...month.next_month.in_time_zone)
        .select(:id, :starts_at, :body_name, :committee_id, :status).to_a

      # Canonical selection needs association presence, never reporting text.
      [ :meeting_documents, :meeting_summaries ].each do |association|
        model = Meeting.reflect_on_association(association).klass
        ActiveRecord::Associations::Preloader.new(
          records: meetings, associations: association, scope: model.select(:id, :meeting_id)
        ).call
      end

      meetings.group_by(&:duplicate_identity_key).values
        .map { |duplicates| Meeting.preferred_duplicate(duplicates) }
        .sort_by { |meeting| [ meeting.starts_at, meeting.id ] }.reverse
    end
  end
end
