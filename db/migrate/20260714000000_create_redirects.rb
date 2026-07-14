class CreateRedirects < ActiveRecord::Migration[8.1]
  def change
    create_table :redirects do |t|
      t.string :source_path, null: false
      t.string :destination, null: false
      t.integer :status_code, null: false, default: 301
      t.text :note
      t.integer :hits, null: false, default: 0
      t.timestamps

      t.index :source_path, unique: true
    end
  end
end
