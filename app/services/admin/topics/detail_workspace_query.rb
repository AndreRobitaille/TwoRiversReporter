module Admin
  module Topics
    class DetailWorkspaceQuery
      Workspace = Data.define(
        :topic,
        :aliases,
        :recent_history,
        :recent_evidence,
        :appearance_count,
        :agenda_item_count,
        :alias_count,
        :has_single_alias,
        :summary_count,
        :decision_count,
        :vote_count,
        :future_appearance_count,
        :last_seen_at,
        :last_activity_at,
        :signals,
        :pinned
      )

      def initialize(topic:)
        @topic = topic
      end

      def call
        Workspace.new(
          topic: topic,
          aliases: topic.topic_aliases.order(:name),
          recent_history: topic.topic_review_events.includes(:user).order(created_at: :desc).limit(5),
          recent_evidence: topic.agenda_items
                                .includes(:meeting_documents, meeting: { meeting_documents: :extractions })
                                .order("meetings.starts_at DESC")
                                .limit(3),
          appearance_count: topic.topic_appearances.count,
          agenda_item_count: topic.agenda_items.count,
          alias_count: topic.topic_aliases.count,
          has_single_alias: topic.topic_aliases.count == 1,
          summary_count: topic.topic_summaries.count,
          decision_count: topic.agenda_items.joins(:motions).count,
          vote_count: topic.agenda_items.joins(motions: :votes).count,
          future_appearance_count: topic.agenda_items.joins(:meeting).where("meetings.starts_at > ?", Time.current).distinct.count,
          last_seen_at: topic.last_seen_at,
          last_activity_at: topic.last_activity_at,
          signals: build_signals,
          pinned: topic.pinned?
        )
      end

      private

      attr_reader :topic

      def build_signals
        signals = []
        signals << "Needs review" if topic.review_status == "proposed"
        signals << "Blocked" if topic.status == "blocked"
        signals << "Pinned" if topic.pinned?
        signals << "Alias-heavy" if topic.topic_aliases.count >= 3
        signals
      end
    end
  end
end
