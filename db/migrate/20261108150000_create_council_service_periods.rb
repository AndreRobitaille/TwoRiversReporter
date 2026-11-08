class CreateCouncilServicePeriods < ActiveRecord::Migration[8.1]
  def change
    create_table :council_service_periods do |t|
      t.references :member, null: false, foreign_key: true
      t.string :period_key, null: false
      t.date :started_on, null: false
      t.date :ended_on
      t.references :start_source_version, null: false, foreign_key: { to_table: :meeting_document_versions }
      t.integer :start_page, null: false
      t.references :end_source_version, foreign_key: { to_table: :meeting_document_versions }
      t.integer :end_page
      t.timestamps
    end

    add_index :council_service_periods, [ :member_id, :period_key ], unique: true
  end
end
