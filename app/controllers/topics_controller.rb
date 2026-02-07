class TopicsController < ApplicationController
  def index
    @topics = Topic.publicly_visible
                   .joins(:agenda_items)
                   .group(:id)
                   .order("count(agenda_items.id) DESC")
  end

  def show
    @topic = Topic.publicly_visible.find(params[:id])
    @items = @topic.agenda_items.includes(:meeting).order("meetings.starts_at DESC")
  rescue ActiveRecord::RecordNotFound
    redirect_to topics_path, alert: "Topic not found."
  end
end
