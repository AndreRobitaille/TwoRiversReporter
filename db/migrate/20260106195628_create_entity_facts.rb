class CreateEntityFacts < ActiveRecord::Migration[8.1]
  def change
    create_table :entity_facts do |t|
      t.references :entity, null: false, foreign_key: true
      t.text :fact_text
      t.string :status
      t.boolean :sensitive
      t.date :verified_on
      t.text :verification_notes
      t.string :source_type
      t.json :source_ref

      t.timestamps
    end
  end
end
