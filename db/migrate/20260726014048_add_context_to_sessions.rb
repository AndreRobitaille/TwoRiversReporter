class AddContextToSessions < ActiveRecord::Migration[8.1]
  def up
    add_column :sessions, :ip_prefix, :string
    add_column :sessions, :device_fingerprint, :string
    add_column :sessions, :reauthenticated_at, :datetime

    # Derived from the ip_address and user_agent already on every row. Without
    # this, the deploy that adds the context gate challenges every live session
    # at once, including the owner's.
    #
    # reauthenticated_at is seeded from created_at because the user genuinely
    # did authenticate then. An old timestamp is not fresh, so this grants
    # nothing to a stale session.
    say_with_time "backfilling session context" do
      SessionContextBackfill.run!
    end
  end

  def down
    remove_column :sessions, :ip_prefix
    remove_column :sessions, :device_fingerprint
    remove_column :sessions, :reauthenticated_at
  end
end
