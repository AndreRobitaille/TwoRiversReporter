class AddDescriptionGeneratedAtToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :description_generated_at, :datetime
  end
end
