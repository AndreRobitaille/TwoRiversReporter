class AddPasswordlessFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :status, :string
    add_column :users, :email_verified_at, :datetime
    add_column :users, :disabled_at, :datetime
    add_column :users, :webauthn_id, :string
    add_column :users, :passkey_prompt_dismissed_until, :datetime

    add_index :users, :webauthn_id, unique: true
    add_index :users, :status

    change_column_default :users, :status, from: nil, to: "pending"
  end
end
