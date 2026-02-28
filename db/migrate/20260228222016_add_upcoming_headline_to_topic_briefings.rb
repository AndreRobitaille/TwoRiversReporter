class AddUpcomingHeadlineToTopicBriefings < ActiveRecord::Migration[8.1]
  def change
    add_column :topic_briefings, :upcoming_headline, :string
  end
end
