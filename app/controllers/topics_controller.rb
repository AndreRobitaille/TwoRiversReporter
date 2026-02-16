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

    # Build highlight signals from recent continuity events
    @highlight_signals = build_highlight_signals
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

  HIGHLIGHT_WINDOW = 30.days

  HIGHLIGHT_EVENT_TYPES = %w[
    agenda_recurrence
    deferral_signal
    cross_body_progression
    disappearance_signal
    rules_engine_update
  ].freeze

  def build_highlight_signals
    events = TopicStatusEvent
      .where(topic_id: Topic.publicly_visible.select(:id))
      .where(evidence_type: HIGHLIGHT_EVENT_TYPES)
      .where(occurred_at: HIGHLIGHT_WINDOW.ago..)
      .select(:topic_id, :evidence_type, :lifecycle_status)

    signals = {}
    events.each do |event|
      label = helpers.highlight_signal_label(event.evidence_type, event.lifecycle_status)
      next unless label

      signals[event.topic_id] ||= []
      signals[event.topic_id] << label unless signals[event.topic_id].include?(label)
    end
    signals
  end

  def group_last_activity_sort_key(last_activity_at)
    return 0 unless last_activity_at

    -last_activity_at.to_i
  end
end
