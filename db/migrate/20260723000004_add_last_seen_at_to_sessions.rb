class AddLastSeenAtToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :last_seen_at, :datetime unless column_exists?(:sessions, :last_seen_at)

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE sessions
          SET last_seen_at = CURRENT_TIMESTAMP
          WHERE last_seen_at IS NULL
        SQL
      end
    end
  end
end
