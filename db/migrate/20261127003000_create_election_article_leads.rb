class CreateElectionArticleLeads < ActiveRecord::Migration[8.1]
  def change
    create_table :election_article_leads do |t|
      t.date :election_on, null: false
      t.string :source_url, null: false
      t.date :published_on, null: false
      t.timestamps
    end
    add_index :election_article_leads, :source_url, unique: true
    add_index :election_article_leads, :election_on
  end
end
