class TopicsController < ApplicationController
  def index
    # Fetch all publicly visible topics
    base_scope = Topic.publicly_visible
                      .joins(:agenda_items)
                      .group(:id)
                      .select("topics.*, COUNT(agenda_items.id) as agenda_item_count_cache")

    # Recently updated topics across all statuses
    @recent_topics = base_scope.where.not(last_activity_at: nil)
                               .order(last_activity_at: :desc)
                               .limit(6)

    # Group by lifecycle status
    @grouped_topics = base_scope.order(last_activity_at: :desc)
                               .group_by(&:lifecycle_status)
                               .transform_keys { |k| k.presence || "unknown" }
                               .sort_by { |status, _| status_order(status) }
  end

  private

  def status_order(status)
    case status
    when "active" then 0
    when "recurring" then 1
    when "dormant" then 2
    when "resolved" then 3
    else 4
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
