class TopicsController < ApplicationController
  include HighlightSignals

  def index
    active_scope = Topic.publicly_visible
                        .active
                        .joins(:agenda_items)
                        .group("topics.id")
                        .select("topics.*, COUNT(agenda_items.id) as agenda_item_count_cache")

    # Hero: high-impact active topics with recent activity (30 days), ranked by impact
    @hero_topics = active_scope
                     .where(last_activity_at: 30.days.ago..)
                     .order(Arel.sql("resident_impact_score DESC NULLS LAST"), last_activity_at: :desc)
                     .limit(6)

    # Main list: remaining active topics, excluding hero, paginated
    hero_ids = @hero_topics.map(&:id)
    remaining_scope = active_scope
                        .where.not(id: hero_ids)
                        .order(last_activity_at: :desc)

    @pagy, @topics = pagy(remaining_scope, limit: 20)

    # Highlight signals for all visible topics
    visible_ids = (hero_ids + @topics.map(&:id)).uniq
    @highlight_signals = build_highlight_signals(visible_ids)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def explore
  end

  def show
    @topic = Topic.publicly_visible.find(params[:id])

    # Eager load data for the timeline
    @appearances = @topic.topic_appearances
                         .includes(:meeting, agenda_item: { motions: { votes: :member } })
                         .order(appeared_at: :desc)

    # Load status events
    @status_events = @topic.topic_status_events.order(occurred_at: :desc)

    # Merge and sort for display
    @timeline_items = (@appearances + @status_events).sort_by do |item|
      item.try(:appeared_at) || item.try(:occurred_at) || Time.at(0)
    end.reverse
  rescue ActiveRecord::RecordNotFound
    redirect_to topics_path, alert: "Topic not found."
  end
end
