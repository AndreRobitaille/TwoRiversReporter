class AddPasswordlessFieldsToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :status, :string
    add_column :users, :email_verified_at, :datetime
    add_column :users, :disabled_at, :datetime
    add_column :users, :webauthn_id, :string
    add_column :users, :passkey_prompt_dismissed_until, :datetime

    add_index :users, :webauthn_id, unique: true
    add_index :users, :status

    reversible do |dir|
      dir.up do
        users = Class.new(ActiveRecord::Base) do
          self.table_name = "users"
        end

        users.reset_column_information
        users.find_each do |user|
          user.update_columns(
            status: user.status.presence || "pending",
            webauthn_id: user.webauthn_id.presence || WebAuthn.generate_user_id
          )
        end
      end
    end

    change_column_default :users, :status, from: nil, to: "pending"
  end
end
