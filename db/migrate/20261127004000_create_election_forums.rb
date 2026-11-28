class CreateElectionForums < ActiveRecord::Migration[8.1]
  def change
    create_table :election_forums do |t|
      t.date :election_on, null: false
      t.date :held_on, null: false
      t.string :organizer, null: false
      t.string :announcement_url, null: false
      t.jsonb :recordings, null: false, default: {}
      t.timestamps
      t.index [ :election_on, :held_on, :organizer ], unique: true
    end
  end
end
