module ResidentContent
  class HomeSelection
    ACTIVITY_WINDOW = 30.days
    TOP_STORY_LIMIT = 2
    WIRE_MIN_IMPACT = 2
    WIRE_CARD_COUNT = 4
    WIRE_ROW_LIMIT = 6
    NEXT_UP_LIMIT = 2

    COUNCIL_PATTERNS = [
      "City Council Meeting",
      "City Council Work Session",
      "City Council Special Meeting"
    ].freeze

    def call
      stories = GeneratedImages::HomepageTopicSelector.new.call.first(TOP_STORY_LIMIT)
      # Meeting timestamps tie often; keep topic ordering stable across selections.
      wire = Topic.reusable.where("resident_impact_score >= ?", WIRE_MIN_IMPACT)
        .where("last_activity_at > ?", ACTIVITY_WINDOW.ago).where.not(id: stories.map(&:id))
        .includes(:topic_briefing).order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)
        .limit(WIRE_CARD_COUNT + WIRE_ROW_LIMIT).to_a
      upcoming = Meeting.where("starts_at > ?", Time.current).where(body_name: COUNCIL_PATTERNS)
        .includes(:meeting_documents, :meeting_summaries).order(starts_at: :asc, id: :asc).limit(NEXT_UP_LIMIT)
      { top_stories: stories, wire_cards: wire.first(WIRE_CARD_COUNT),
        wire_rows: wire.drop(WIRE_CARD_COUNT), next_up: upcoming.to_a }
    end
  end
end
