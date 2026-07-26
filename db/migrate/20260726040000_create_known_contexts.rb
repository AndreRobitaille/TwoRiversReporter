class CreateKnownContexts < ActiveRecord::Migration[8.1]
  def change
    create_table :known_contexts do |t|
      t.references :user, null: false, foreign_key: true
      t.string :ip_prefix
      t.string :device_fingerprint
      t.datetime :last_seen_at, null: false

      t.timestamps
    end

    # nulls_not_distinct: without it, Postgres treats two NULLs as unequal for
    # uniqueness purposes, so two rows for the same user and ip_prefix with a
    # NULL device_fingerprint (a request with no User-Agent) would not collide
    # and a race between them would not be caught by the database at all.
    add_index :known_contexts, [ :user_id, :ip_prefix, :device_fingerprint ],
      unique: true, nulls_not_distinct: true, name: "index_known_contexts_on_user_and_context"
    add_index :known_contexts, :last_seen_at
  end
end
