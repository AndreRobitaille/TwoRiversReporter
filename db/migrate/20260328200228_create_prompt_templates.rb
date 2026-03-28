class CreatePromptTemplates < ActiveRecord::Migration[8.1]
  def change
    create_table :prompt_templates do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description
      t.text :system_role
      t.text :instructions, null: false
      t.string :model_tier, null: false, default: "default"
      t.jsonb :placeholders, null: false, default: []
      t.timestamps
    end

    add_index :prompt_templates, :key, unique: true

    create_table :prompt_versions do |t|
      t.references :prompt_template, null: false, foreign_key: true
      t.text :system_role
      t.text :instructions, null: false
      t.string :model_tier, null: false
      t.string :editor_note
      t.datetime :created_at, null: false
    end

    add_index :prompt_versions, [:prompt_template_id, :created_at]
  end
end
