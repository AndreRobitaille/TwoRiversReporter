class AddExtractionFieldsToKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    add_column :knowledge_sources, :origin, :string, default: "manual", null: false
    add_column :knowledge_sources, :reasoning, :text
    add_column :knowledge_sources, :confidence, :float

    # Backfill existing status column with "approved" for all existing records
    # (status column exists but was unused — now it drives triage workflow)
    change_column_default :knowledge_sources, :status, from: nil, to: "approved"
    reversible do |dir|
      dir.up do
        execute "UPDATE knowledge_sources SET status = 'approved' WHERE status IS NULL"
        execute "UPDATE knowledge_sources SET origin = 'manual'"
      end
    end

    add_index :knowledge_sources, :origin
    add_index :knowledge_sources, :status
  end
end
