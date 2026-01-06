class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.boolean :admin, null: false, default: false

      t.string :totp_secret
      t.boolean :totp_enabled, null: false, default: false
      t.text :recovery_codes_digest, null: false, default: [], array: true

      t.timestamps
    end
    add_index :users, :email_address, unique: true
  end
end
