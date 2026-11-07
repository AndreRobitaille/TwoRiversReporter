class CreateCouncilDecisionCorrections < ActiveRecord::Migration[8.1]
  def up
    create_table :council_decision_corrections do |t|
      t.references :observation, null: false, foreign_key: { to_table: :council_decision_observations }
      t.references :basis_observation, foreign_key: { to_table: :council_decision_observations }
      t.references :before_decision, foreign_key: { to_table: :council_decisions }
      t.references :after_decision, foreign_key: { to_table: :council_decisions }
      t.references :previous_correction, foreign_key: { to_table: :council_decision_corrections }
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.bigint :original_actor_id, null: false
      t.string :actor_email, null: false
      t.string :action, null: false
      t.text :reason, null: false
      t.string :request_id, null: false
      t.jsonb :request_manifest, null: false
      t.jsonb :evidence_manifest, null: false
      t.timestamps
    end
    add_index :council_decision_corrections, :request_id, unique: true

    create_table :council_decision_assignments do |t|
      t.references :observation, null: false, foreign_key: { to_table: :council_decision_observations }, index: { unique: true }
      t.references :minutes_extraction, null: false, foreign_key: true
      t.references :council_decision, foreign_key: true
      t.references :correction, foreign_key: { to_table: :council_decision_corrections }
      t.jsonb :conflicting_correction_ids, null: false, default: []
      t.timestamps
    end
    add_index :council_decision_assignments, [ :minutes_extraction_id, :council_decision_id ], unique: true,
      name: "index_decision_assignments_on_stage_and_decision"
    execute <<~SQL
      INSERT INTO council_decision_assignments (observation_id, minutes_extraction_id, council_decision_id, created_at, updated_at)
      SELECT id, minutes_extraction_id, council_decision_id, created_at, updated_at
      FROM council_decision_observations
    SQL
  end

  def down
    if select_value("SELECT COUNT(*) FROM council_decision_corrections").to_i.positive?
      raise ActiveRecord::IrreversibleMigration, "Retain reviewed identity history; roll back code without dropping these tables"
    end
    drop_table :council_decision_assignments
    drop_table :council_decision_corrections
  end
end
