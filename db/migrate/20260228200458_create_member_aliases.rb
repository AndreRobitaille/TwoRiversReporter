class CreateMemberAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :member_aliases do |t|
      t.references :member, null: false, foreign_key: true
      t.string :name, null: false
      t.timestamps
    end
    add_index :member_aliases, :name, unique: true
  end
end
