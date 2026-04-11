class DedupeAndUniqueTopicAppearances < ActiveRecord::Migration[8.1]
  def up
    # Clean up duplicate rows (same topic + meeting + agenda_item). Keeps the
    # lowest-id row in each group. Duplicates came from a race in
    # AgendaItemTopic#create_appearance_and_update_continuity where the
    # exists? check + create! sequence wasn't atomic.
    execute <<~SQL
      DELETE FROM topic_appearances
      WHERE id NOT IN (
        SELECT min_id FROM (
          SELECT MIN(id) AS min_id
          FROM topic_appearances
          GROUP BY topic_id, meeting_id, agenda_item_id
        ) survivors
      )
    SQL

    # Unique index prevents future duplicates at the DB level.
    # Postgres treats NULL values as distinct by default, so rows with
    # agenda_item_id: nil are not considered duplicates of each other
    # (which is fine — those come from non-agenda evidence sources).
    add_index :topic_appearances,
              [ :topic_id, :meeting_id, :agenda_item_id ],
              unique: true,
              name: "idx_topic_appearances_unique_triple"
  end

  def down
    remove_index :topic_appearances, name: "idx_topic_appearances_unique_triple"
  end
end
