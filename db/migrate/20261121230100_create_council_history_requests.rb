class CreateCouncilHistoryRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :council_history_requests do |t|
      t.bigint :meeting_id, null: false
      t.string :stage, null: false
      t.string :request_digest, null: false
      t.string :model, null: false
      t.boolean :pilot, null: false
      t.integer :reserved_microusd, null: false
      t.integer :charged_microusd, null: false
      t.jsonb :usage
      t.string :provider_response_id
      t.datetime :finished_at
      t.timestamps
      t.index [ :meeting_id, :stage, :request_digest ]
    end
  end
end
