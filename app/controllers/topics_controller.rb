class TopicsController < ApplicationController
  include HighlightSignals

  def index
    base_scope = Topic.publicly_visible
                      .joins(:agenda_items)
                      .group("topics.id")
                      .select("topics.*, COUNT(agenda_items.id) as agenda_item_count_cache")
                      .order(last_activity_at: :desc)

    # Recently updated topics (hero section — always first 6)
    @recent_topics = base_scope.where.not(last_activity_at: nil).limit(6)

    # Paginated flat list
    @pagy, @topics = pagy(base_scope, limit: 20)

    # Only compute highlight signals for visible topics
    visible_ids = (@recent_topics.map(&:id) + @topics.map(&:id)).uniq
    @highlight_signals = build_highlight_signals(visible_ids)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
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
