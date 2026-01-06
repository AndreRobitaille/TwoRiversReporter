class HomeController < ApplicationController
  def index
    @upcoming_meetings = Meeting.where("starts_at > ?", Time.current)
                                .order(starts_at: :asc)
                                .limit(5)

    @recent_meetings = Meeting.where("starts_at <= ?", Time.current)
                              .order(starts_at: :desc)
                              .limit(5)

    @recent_topics = Topic.joins(:agenda_items)
                          .select("topics.*, COUNT(agenda_item_topics.id) as items_count")
                          .group("topics.id")
                          .order("items_count DESC")
                          .limit(8)
  end
end
