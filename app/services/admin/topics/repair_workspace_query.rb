module Admin
  module Topics
    class RepairWorkspaceQuery
      Workspace = Data.define(:topic, :alias_count, :mention_count, :recent_activity)

      def initialize(topic:)
        @topic = topic
      end

      def call
        Workspace.new(
          topic: topic,
          alias_count: topic.topic_aliases.count,
          mention_count: topic.agenda_items.count,
          recent_activity: topic.topic_review_events.includes(:user).order(created_at: :desc).limit(3)
        )
      end

      private

      attr_reader :topic
    end
  end
end
