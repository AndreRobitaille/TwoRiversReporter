class CreateVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :votes do |t|
      t.references :motion, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :value

      t.timestamps
    end
  end
end
