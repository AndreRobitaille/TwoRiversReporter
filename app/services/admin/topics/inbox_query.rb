module Admin
  module Topics
    class InboxQuery
      Row = Data.define(
        :topic_id,
        :name,
        :description,
        :status,
        :review_status,
        :lifecycle_status,
        :pinned,
        :alias_count,
        :alias_names,
        :mention_count,
        :reason_label,
        :signals,
        :updated_at,
        :created_at,
        :last_seen_at,
        :last_activity_at
      )

      def initialize(scope: Topic.all, sort: "updated_at")
        @scope = scope
        @sort = sort
      end

      def call
        rows = flagged_scope.map do |topic|
          Row.new(
            topic_id: topic.id,
            name: topic.name,
            description: topic.description,
            status: topic.status,
            review_status: topic.review_status,
            lifecycle_status: topic.lifecycle_status,
            pinned: topic.pinned?,
            alias_count: topic.topic_aliases.size,
            alias_names: topic.topic_aliases.map(&:name).sort,
            mention_count: topic.agenda_items.size,
            reason_label: reason_for(topic),
            signals: signals_for(topic),
            updated_at: topic.updated_at,
            created_at: topic.created_at,
            last_seen_at: topic.last_seen_at,
            last_activity_at: topic.last_activity_at
          )
        end

        sort_rows(rows)
      end

      private

      attr_reader :scope, :sort

      def flagged_scope
        scope.includes(:topic_aliases, :agenda_items)
             .reorder(updated_at: :desc)
             .limit(200)
      end

      def reason_for(topic)
        return "Needs review" if topic.review_status == "proposed"
        return "Blocked topic" if topic.status == "blocked"
        return "Alias cleanup" if topic.topic_aliases.any?

        "Recently changed"
      end

      def signals_for(topic)
        [].tap do |signals|
          signals << "Pinned" if topic.pinned?
          signals << "Needs review" if topic.review_status == "proposed"
          signals << "Blocked" if topic.status == "blocked"
          signals << topic.lifecycle_status.to_s.capitalize if topic.lifecycle_status.in?(%w[dormant resolved recurring])
          signals << "No description" if topic.description.blank?
          signals << "Zero mentions" if topic.agenda_items.empty?
          signals << "Many aliases" if topic.topic_aliases.size >= 3
          signals << "New" if topic.created_at >= 7.days.ago
        end
      end

      def sort_rows(rows)
        case sort
        when "alias_count"
          rows.sort_by { |row| [ -row.alias_count, row.name ] }
        when "mention_count"
          rows.sort_by { |row| [ -row.mention_count, row.name ] }
        when "last_seen_at"
          rows.sort_by { |row| [ row.last_seen_at ? 0 : 1, -(row.last_seen_at&.to_i || 0), row.name ] }
        when "last_activity_at"
          rows.sort_by { |row| [ row.last_activity_at ? 0 : 1, -(row.last_activity_at&.to_i || 0), row.name ] }
        when "created_at"
          rows.sort_by { |row| [ -(row.created_at&.to_i || 0), row.name ] }
        when "name"
          rows.sort_by(&:name)
        else
          rows.sort_by { |row| [ -(row.updated_at&.to_i || 0), row.name ] }
        end
      end
    end
  end
end
