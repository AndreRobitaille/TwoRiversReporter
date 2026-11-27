class CreateCandidatePortraits < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:candidate_portraits)
      consolidate_existing_selections if table_exists?(:portrait_subjects)
      copy_source_credits
    else
      create_table :candidate_portraits do |t|
        t.string :name, null: false, index: { unique: true }
        t.references :member, index: { unique: true }, foreign_key: { on_delete: :nullify }
        t.string :image_url, null: false
        t.string :source_url, null: false
        t.string :publisher, null: false
        t.binary :thumbnail, null: false
        t.timestamps
      end
    end

    names = select_values("SELECT DISTINCT jsonb_object_keys(questionnaire_portraits) FROM campaign_sources")
    names |= Campaigns::LatestPortrait.catalog.keys
    ActiveRecord.after_all_transactions_commit { names.each { |name| RefreshCandidatePortraitJob.perform_later(name) } }
  end

  def down
    drop_table :candidate_portraits
  end

  private

  def copy_source_credits
    add_column :candidate_portraits, :source_url, :string
    add_column :candidate_portraits, :publisher, :string
    execute <<~SQL
      UPDATE candidate_portraits SET source_url = versions.source_url, publisher = versions.publisher
      FROM campaign_source_versions versions WHERE versions.id = candidate_portraits.campaign_source_version_id
    SQL
    change_column_null :candidate_portraits, :source_url, false
    change_column_null :candidate_portraits, :publisher, false
    remove_reference :candidate_portraits, :campaign_source_version, foreign_key: true
  end

  # The development preview used a separate row for every proposed image.
  def consolidate_existing_selections
    add_column :candidate_portraits, :name, :string
    add_reference :candidate_portraits, :member, index: { unique: true }, foreign_key: { on_delete: :nullify }

    execute <<~SQL
      DELETE FROM candidate_portraits
      WHERE id NOT IN (SELECT current_portrait_id FROM portrait_subjects WHERE current_portrait_id IS NOT NULL)
    SQL
    execute <<~SQL
      UPDATE candidate_portraits SET name = subjects.name, member_id = subjects.member_id
      FROM portrait_subjects subjects WHERE subjects.current_portrait_id = candidate_portraits.id
    SQL
    change_column_null :candidate_portraits, :name, false
    change_column_null :candidate_portraits, :thumbnail, false
    add_index :candidate_portraits, :name, unique: true
    remove_reference :candidate_portraits, :portrait_subject, foreign_key: true
    remove_column :candidate_portraits, :reviewed_at
    remove_column :candidate_portraits, :credit
    drop_table :portrait_subjects
  end
end
