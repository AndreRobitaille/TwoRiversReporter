class HomeController < ApplicationController
  ACTIVITY_WINDOW = 30.days
  TOP_STORY_MIN_IMPACT = 4
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

  def index
    @top_stories = build_top_stories
    wire_all = build_wire(@top_stories.map(&:id))
    @wire_cards = wire_all.first(WIRE_CARD_COUNT)
    @wire_rows = wire_all.drop(WIRE_CARD_COUNT).first(WIRE_ROW_LIMIT)
    @next_up = build_next_up
    load_headlines(@top_stories + @wire_cards + @wire_rows)
    load_meeting_refs(@top_stories + @wire_cards + @wire_rows)
  end

  private

  # `id: :desc` tiebreaker is load-bearing — topic last_activity_at values
  # cluster on meeting-start hours (multiple topics share the exact same
  # timestamp). Without a stable tiebreaker, the same topic can appear in
  # both @top_stories and @wire_cards across the same request's queries.

  def build_top_stories
    Topic.approved
      .where("resident_impact_score >= ?", TOP_STORY_MIN_IMPACT)
      .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
      .order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)
      .limit(TOP_STORY_LIMIT)
      .to_a
  end

  def build_wire(exclude_ids)
    scope = Topic.approved
      .where("resident_impact_score >= ?", WIRE_MIN_IMPACT)
      .where("last_activity_at > ?", ACTIVITY_WINDOW.ago)
      .order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)

    scope = scope.where.not(id: exclude_ids) if exclude_ids.any?
    scope.limit(WIRE_CARD_COUNT + WIRE_ROW_LIMIT).to_a
  end

  def build_next_up
    Meeting
      .where("starts_at > ?", Time.current)
      .where(body_name: COUNCIL_PATTERNS)
      .order(starts_at: :asc)
      .limit(NEXT_UP_LIMIT)
  end

  def load_headlines(topics)
    return if topics.empty?

    @headlines = TopicBriefing
      .where(topic_id: topics.map(&:id))
      .each_with_object({}) { |b, h| h[b.topic_id] = b.headline if b.headline.present? }
  end

  def load_meeting_refs(topics)
    return if topics.empty?

    topic_ids = topics.map(&:id)

    latest_appearances = TopicAppearance
      .joins(:meeting)
      .where(topic_id: topic_ids)
      .select("DISTINCT ON (topic_appearances.topic_id) topic_appearances.topic_id, meetings.id AS meeting_id, meetings.body_name, meetings.starts_at")
      .order(Arel.sql("topic_appearances.topic_id, meetings.starts_at DESC"))

    @meeting_refs = latest_appearances.each_with_object({}) do |row, h|
      h[row.topic_id] = {
        meeting_id: row.meeting_id,
        body_name: row.body_name,
        date: row.starts_at
      }
    end
  end
end
