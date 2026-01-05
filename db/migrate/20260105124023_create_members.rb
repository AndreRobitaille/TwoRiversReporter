class CreateMembers < ActiveRecord::Migration[8.1]
  def change
    create_table :members do |t|
      t.string :name

      t.timestamps
    end
    add_index :members, :name
  end
end
