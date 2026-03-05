class CreateCommitteesAndRelatedTables < ActiveRecord::Migration[8.1]
  def change
    create_table :committees do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :committee_type, null: false, default: "city"
      t.string :status, null: false, default: "active"
      t.date :established_on
      t.date :dissolved_on

      t.timestamps
    end

    add_index :committees, :name, unique: true
    add_index :committees, :slug, unique: true

    create_table :committee_aliases do |t|
      t.references :committee, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :committee_aliases, :name, unique: true

    create_table :committee_memberships do |t|
      t.references :committee, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :role
      t.date :started_on
      t.date :ended_on
      t.string :source, null: false, default: "admin_manual"

      t.timestamps
    end

    add_index :committee_memberships, [ :committee_id, :member_id, :ended_on ],
              name: "idx_committee_memberships_unique_active",
              unique: true,
              where: "ended_on IS NULL"

    add_reference :meetings, :committee, foreign_key: true, null: true
    add_reference :topic_appearances, :committee, foreign_key: true, null: true
  end
end
