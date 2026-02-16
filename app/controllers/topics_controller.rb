class TopicsController < ApplicationController
  def index
    @topics = Topic.publicly_visible
                   .joins(:agenda_items)
                   .group(:id)
                   .order("count(agenda_items.id) DESC")
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
