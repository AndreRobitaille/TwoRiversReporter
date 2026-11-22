class CreateCouncilTermSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :council_term_summaries do |t|
      t.references :member, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.date :election_on, null: false
      t.date :attempted_cycle
      t.string :evidence_digest
      t.jsonb :sentences, default: [], null: false
      t.jsonb :promise_assessments, default: [], null: false
      t.datetime :generated_at
      t.index [ :member_id, :election_on ], unique: true
    end

    add_column :council_ai_reservations, :provider_usage, :jsonb
  end
end
