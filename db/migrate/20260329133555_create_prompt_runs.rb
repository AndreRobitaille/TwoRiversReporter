class CreatePromptRuns < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_runs do |t|
      t.string :prompt_template_key, null: false
      t.string :ai_model, null: false
      t.jsonb :messages, null: false, default: []
      t.text :response_body, null: false
      t.string :response_format
      t.float :temperature
      t.integer :duration_ms
      t.jsonb :placeholder_values
      t.string :source_type
      t.bigint :source_id
      t.datetime :created_at, null: false
    end

    add_index :prompt_runs, [ :prompt_template_key, :created_at ]
    add_index :prompt_runs, [ :source_type, :source_id ]
  end
end
