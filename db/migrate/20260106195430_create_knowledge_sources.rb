class CreateKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    create_table :knowledge_sources do |t|
      t.string :title
      t.string :source_type
      t.text :body
      t.string :status
      t.date :verified_on
      t.text :verification_notes
      t.boolean :active

      t.timestamps
    end
  end
end
