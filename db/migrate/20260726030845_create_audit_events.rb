class CreateAuditEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :audit_events do |t|
      t.references :actor, foreign_key: { to_table: :users }, null: true
      # Snapshot. The whole point of this table is to survive the deletion of
      # the things it names, and a foreign key alone does not.
      t.string :actor_email
      t.string :action, null: false
      t.string :subject_type
      t.bigint :subject_id
      t.string :subject_label
      t.jsonb :metadata, null: false, default: {}
      t.string :ip_address

      t.timestamps
    end

    add_index :audit_events, [ :subject_type, :subject_id ]
    add_index :audit_events, :created_at
  end
end
