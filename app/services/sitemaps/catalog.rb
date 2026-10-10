module Sitemaps
  class Catalog
    include Rails.application.routes.url_helpers

    Entry = Data.define(:path, :lastmod)

    def call
      entries = [ topics_path, meetings_path, committees_path ].map { |path| entry(path) }
      entries + topic_entries + meeting_entries + committee_entries + member_entries
    end

    private

      def topic_entries
        modified = [ TopicBriefing, TopicAppearance, TopicSummary ].map do |model|
          model.group(:topic_id).maximum(:updated_at)
        end
        Topic.publicly_visible.order(:id).pluck(:id, :updated_at).map do |id, updated_at|
          entry(topic_path(id), updated_at, *modified.map { |dates| dates[id] })
        end
      end

      def meeting_entries
        meetings = Meeting.order(:id).select(:id, :starts_at, :committee_id, :body_name, :status, :updated_at).to_a
        # Canonical selection needs association presence, not document or summary text.
        [ :meeting_documents, :meeting_summaries ].each do |association|
          model = Meeting.reflect_on_association(association).klass
          ActiveRecord::Associations::Preloader.new(
            records: meetings, associations: association,
            scope: model.select(:id, :meeting_id, :updated_at)
          ).call
        end
        modified = [ AgendaItem, Motion ].map { |model| model.group(:meeting_id).maximum(:updated_at) }
        meetings.group_by(&:duplicate_identity_key).values.map do |duplicates|
          meeting = Meeting.preferred_duplicate(duplicates)
          timestamps = (meeting.meeting_documents + meeting.meeting_summaries).map(&:updated_at)
          entry(meeting_path(meeting), meeting.updated_at, *timestamps, *modified.map { |dates| dates[meeting.id] })
        end
      end

      def committee_entries
        Committee.where(status: %w[active dormant]).order(:id).pluck(:slug).map do |slug|
          entry(committee_path(slug))
        end
      end

      def member_entries
        Member.order(:id).pluck(:id).map { |id| entry(member_path(id)) }
      end

      def entry(path, *timestamps)
        Entry.new(path: path, lastmod: timestamps.compact.max)
      end
  end
end
