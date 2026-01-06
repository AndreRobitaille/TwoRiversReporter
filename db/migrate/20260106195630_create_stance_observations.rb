class CreateStanceObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :stance_observations do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: true
      t.references :meeting_document, null: false, foreign_key: true
      t.integer :page_number
      t.string :topic
      t.string :position
      t.float :sentiment
      t.text :quote
      t.float :confidence

      t.timestamps
    end
  end
end
