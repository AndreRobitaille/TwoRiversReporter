class AddCanonicalRosterSupport < ActiveRecord::Migration[8.1]
  def up
    add_column :committee_memberships, :position_title, :string
    add_column :committee_memberships, :source_url, :string
    add_column :committee_memberships, :verified_at, :datetime

    remove_index :committee_memberships, name: "idx_committee_memberships_unique_active"
    add_index :committee_memberships, [ :committee_id, :member_id ],
              unique: true,
              where: "ended_on IS NULL",
              name: "idx_committee_memberships_unique_active"

    create_table :member_positions do |t|
      t.references :member, null: false, foreign_key: true
      t.string :kind, null: false
      t.string :title, null: false
      t.string :source, null: false
      t.string :source_url, null: false
      t.date :started_on
      t.date :ended_on
      t.datetime :verified_at, null: false

      t.timestamps
    end

    add_index :member_positions, [ :member_id, :kind ],
              unique: true,
              where: "ended_on IS NULL",
              name: "idx_member_positions_unique_active"
  end

  def down
    drop_table :member_positions

    remove_index :committee_memberships, name: "idx_committee_memberships_unique_active"
    add_index :committee_memberships, [ :committee_id, :member_id, :ended_on ],
              unique: true,
              where: "ended_on IS NULL",
              name: "idx_committee_memberships_unique_active"

    remove_column :committee_memberships, :verified_at
    remove_column :committee_memberships, :source_url
    remove_column :committee_memberships, :position_title
  end
end
