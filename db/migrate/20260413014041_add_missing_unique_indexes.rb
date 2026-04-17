class AddMissingUniqueIndexes < ActiveRecord::Migration[8.0]
  def up
    # Dedupe members before adding unique constraint
    execute <<~SQL
      DELETE FROM members
      WHERE id NOT IN (
        SELECT MIN(id) FROM members GROUP BY LOWER(name)
      )
    SQL

    remove_index :members, :name
    add_index :members, :name, unique: true

    # Dedupe agenda_item_topics before adding unique constraint
    execute <<~SQL
      DELETE FROM agenda_item_topics
      WHERE id NOT IN (
        SELECT MIN(id) FROM agenda_item_topics GROUP BY agenda_item_id, topic_id
      )
    SQL

    add_index :agenda_item_topics, [ :agenda_item_id, :topic_id ],
              unique: true, name: "idx_agenda_item_topics_unique_pair"

    # Dedupe votes before adding unique constraint
    execute <<~SQL
      DELETE FROM votes
      WHERE id NOT IN (
        SELECT MIN(id) FROM votes GROUP BY motion_id, member_id
      )
    SQL

    add_index :votes, [ :motion_id, :member_id ],
              unique: true, name: "idx_votes_unique_per_motion"
  end

  def down
    remove_index :votes, name: "idx_votes_unique_per_motion"
    remove_index :agenda_item_topics, name: "idx_agenda_item_topics_unique_pair"
    remove_index :members, :name
    add_index :members, :name
  end
end
