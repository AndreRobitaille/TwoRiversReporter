class CreateElectionFilingWatches < ActiveRecord::Migration[8.1]
  def change
    create_table :election_filing_watches do |t|
      t.date :election_on, null: false, index: { unique: true }
      t.string :article_url
      t.boolean :stopped, null: false, default: false
      t.timestamps
    end
  end
end
