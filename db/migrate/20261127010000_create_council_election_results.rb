class CreateCouncilElectionResults < ActiveRecord::Migration[8.1]
  def change
    create_table :council_election_results do |t|
      t.date :election_on, null: false, index: { unique: true }
      t.date :confirmed_on, null: false
      t.string :source_url, null: false
      t.string :candidate_names, array: true, null: false
      t.string :winner_names, array: true, null: false
      t.timestamps
    end
  end
end
