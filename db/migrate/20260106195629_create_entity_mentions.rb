class CreateEntityMentions < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_mentions do |t|
      t.references :entity, null: false, foreign_key: true
      t.references :meeting, null: false, foreign_key: true
      t.references :meeting_document, null: false, foreign_key: true
      t.integer :page_number
      t.string :raw_name
      t.text :quote
      t.string :context

      t.timestamps
    end
  end
end
