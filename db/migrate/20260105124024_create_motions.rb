class CreateMotions < ActiveRecord::Migration[8.1]
  def change
    create_table :motions do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :agenda_item, null: true, foreign_key: true
      t.text :description
      t.string :outcome

      t.timestamps
    end
  end
end
