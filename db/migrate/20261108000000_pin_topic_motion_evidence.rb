class PinTopicMotionEvidence < ActiveRecord::Migration[8.1]
  def up
    add_reference :topic_status_events, :decision_observation, foreign_key: { to_table: :council_decision_observations }
    add_index :topic_status_events, [ :topic_id, :decision_observation_id, :evidence_type ], name: "index_topic_events_on_retained_decision"
  end

  def down
    if select_value("SELECT 1 FROM topic_status_events WHERE decision_observation_id IS NOT NULL LIMIT 1")
      raise ActiveRecord::IrreversibleMigration, "Retained topic motion evidence must not be discarded"
    end
    remove_index :topic_status_events, name: "index_topic_events_on_retained_decision"
    remove_reference :topic_status_events, :decision_observation, foreign_key: { to_table: :council_decision_observations }
  end
end
