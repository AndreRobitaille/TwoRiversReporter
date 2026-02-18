class AddResidentImpactToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :resident_impact_score, :integer
    add_column :topics, :resident_impact_overridden_at, :datetime
    add_index :topics, :resident_impact_score
  end
end
