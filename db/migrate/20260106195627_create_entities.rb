class CreateEntities < ActiveRecord::Migration[8.1]
  def change
    create_table :entities do |t|
      t.string :name
      t.string :entity_type
      t.string :status
      t.json :aliases
      t.text :notes

      t.timestamps
    end
  end
end
