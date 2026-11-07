class CreateCouncilDecisionObservations < ActiveRecord::Migration[8.1]
  def change
    create_table :council_decisions do |t|
      t.references :meeting, foreign_key: { on_delete: :nullify }
      t.bigint :original_meeting_id, null: false
      t.string :public_id, null: false
      t.timestamps
    end
    add_index :council_decisions, :public_id, unique: true

    create_table :council_decision_observations do |t|
      t.references :minutes_extraction, null: false, foreign_key: true
      t.references :council_decision, foreign_key: true
      t.integer :sequence, null: false
      t.jsonb :data, null: false
      t.jsonb :location_check, null: false
      t.jsonb :agenda_context, null: false
      t.string :identity_status, null: false
      t.string :reason
      t.jsonb :candidate_decision_ids, default: [], null: false
      t.string :rule_version, null: false
      t.string :evidence_status, default: "extracted", null: false
      t.timestamps
    end
    add_index :council_decision_observations, [ :minutes_extraction_id, :sequence ], unique: true,
      name: "index_decision_observations_on_stage_and_sequence"
    add_index :council_decision_observations, [ :minutes_extraction_id, :council_decision_id ], unique: true,
      name: "index_decision_observations_on_stage_and_decision"
    add_reference :motions, :decision_observation, foreign_key: { to_table: :council_decision_observations }, index: { unique: true }
  end
end
