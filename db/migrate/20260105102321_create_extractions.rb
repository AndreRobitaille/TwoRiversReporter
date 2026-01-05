class CreateExtractions < ActiveRecord::Migration[8.1]
  def change
    create_table :extractions do |t|
      t.references :meeting_document, null: false, foreign_key: true
      t.integer :page_number
      t.text :raw_text
      t.text :cleaned_text

      t.timestamps
    end
  end
end
