class CreateTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :topics do |t|
      t.string :name
      t.text :description

      t.timestamps
    end
    add_index :topics, :name
  end
end
