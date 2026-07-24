class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def up
    create_table :site_settings do |t|
      t.string :access_mode, null: false, default: "open"
      t.integer :singleton_guard, null: false, default: 0
      t.timestamps
    end

    add_index :site_settings, :singleton_guard, unique: true

    # Seed explicitly so the intent is visible in the schema rather than
    # implied by a column default.
    execute <<~SQL
      INSERT INTO site_settings (access_mode, singleton_guard, created_at, updated_at)
      VALUES ('open', 0, NOW(), NOW())
    SQL
  end

  def down
    drop_table :site_settings
  end
end
