class HomeController < ApplicationController
  include LoadsGeneratedImages

  allow_unauthenticated_access only: :index

  # Retained for the reanalysis service, which uses the same homepage bounds.
  ACTIVITY_WINDOW = ResidentContent::HomeSelection::ACTIVITY_WINDOW
  WIRE_MIN_IMPACT = ResidentContent::HomeSelection::WIRE_MIN_IMPACT
  WIRE_CARD_COUNT = ResidentContent::HomeSelection::WIRE_CARD_COUNT
  WIRE_ROW_LIMIT = ResidentContent::HomeSelection::WIRE_ROW_LIMIT

  def index
    selection = ResidentContent::HomeSelection.new.call
    @top_stories = selection[:top_stories]
    @wire_cards = selection[:wire_cards]
    @wire_rows = selection[:wire_rows]
    @next_up = selection[:next_up]
    load_headlines(@top_stories + @wire_cards + @wire_rows)
    load_meeting_refs(@top_stories + @wire_cards + @wire_rows)
    @topic_generated_images = generated_images_for(@top_stories + @wire_cards, surface: :og)
  end

  private

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
