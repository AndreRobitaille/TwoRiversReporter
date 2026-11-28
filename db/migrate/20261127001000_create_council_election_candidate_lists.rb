class CreateCouncilElectionCandidateLists < ActiveRecord::Migration[8.1]
  def change
    create_table :council_election_candidate_lists do |t|
      t.date :election_on, null: false, index: { unique: true }
      t.string :names, array: true, null: false
      t.string :source_url
      t.timestamps
    end
  end
end
