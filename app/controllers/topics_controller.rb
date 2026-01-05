class TopicsController < ApplicationController
  def index
    @topics = Topic.joins(:agenda_items).group(:id).order("count(agenda_items.id) DESC")
  end

  def show
    @topic = Topic.find(params[:id])
    @items = @topic.agenda_items.includes(:meeting).order("meetings.starts_at DESC")
  end
end
