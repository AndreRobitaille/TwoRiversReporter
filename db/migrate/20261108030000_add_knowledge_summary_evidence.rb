class AddKnowledgeSummaryEvidence < ActiveRecord::Migration[8.1]
  def change
    add_reference :knowledge_sources, :source_summary, foreign_key: { to_table: :meeting_summaries, on_delete: :nullify }
    add_column :knowledge_sources, :source_summary_manifest, :jsonb
    add_column :knowledge_sources, :evidence_withdrawn_at, :datetime
  end
end
