class AddLastSeenAtToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :last_seen_at, :datetime unless column_exists?(:sessions, :last_seen_at)
  end
end
