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

    # Group by lifecycle status with group metadata
    grouped = base_scope.order(last_activity_at: :desc)
                        .to_a
                        .group_by { |topic| topic.lifecycle_status.presence || "unknown" }

    @grouped_topics = grouped.map do |status, topics|
      {
        status: status,
        topics: topics,
        count: topics.size,
        last_activity_at: topics.map(&:last_activity_at).compact.max
      }
    end.sort_by do |group|
      [ status_order(group[:status]), group_last_activity_sort_key(group[:last_activity_at]) ]
    end
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

  def group_last_activity_sort_key(last_activity_at)
    return 0 unless last_activity_at

    -last_activity_at.to_i
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
