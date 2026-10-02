module Api
  module V1
    class TopicsController < Api::BaseController
      def index
        since, sort = update_filters(default_sort: "activity")
        topics = Topic.publicly_visible.includes(:topic_briefing)
        topics = ResidentQueries.new(search_query).topics.includes(:topic_briefing) if search_query
        if params[:lifecycle].present?
          raise ArgumentError, "Invalid lifecycle." unless %w[active dormant resolved recurring].include?(params[:lifecycle])
          topics = topics.where(lifecycle_status: params[:lifecycle])
        end
        topics = filter_updated_records(topics.reorder(last_activity_at: :desc, id: :desc), since: since)
        topics = updated_records(topics.to_a) if sort == "updated"
        render_collection(topics) { |record| serializer.topic(record) }
      end

      def show
        render_data(serializer.topic_detail(topic))
      end

      def appearances
        records = topic.topic_appearances.includes(:agenda_item, meeting: :meeting_summaries).order(appeared_at: :desc, id: :desc).to_a
        by_date = records.group_by { |entry| entry.appeared_at.to_date.to_s }
        timeline = Array(topic.topic_briefing&.generation_data&.dig("factual_record"))
          .each_with_index.map { |entry, index| serializer.timeline(entry, index, by_date) }
        rows = timeline + records.map { |record| serializer.appearance(record) }
        rows.sort_by! { |entry| [ entry[:date] || entry[:appeared_at].to_s, entry[:index] || entry[:id] ] }
        render_collection(rows.reverse) { |row| row }
      end

      def decisions
        motions = Motion.joins(agenda_item: :agenda_item_topics)
          .where(agenda_item_topics: { topic_id: topic.id }).joins(:meeting)
          .includes(:meeting, votes: :member).order("meetings.starts_at DESC", id: :desc)
        render_collection(motions.reject { |motion| motion.meeting.cancelled? }) { |motion| serializer.motion_payload(motion) }
      end

      private

        def topic
          @topic ||= Topic.publicly_visible.find(params[:id])
        end
    end
  end
end
