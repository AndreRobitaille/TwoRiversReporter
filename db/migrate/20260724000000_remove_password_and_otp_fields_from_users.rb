class RemovePasswordAndOtpFieldsFromUsers < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :password_digest, :string if column_exists?(:users, :password_digest)
    remove_column :users, :totp_enabled, :boolean if column_exists?(:users, :totp_enabled)
    remove_column :users, :totp_secret, :string if column_exists?(:users, :totp_secret)
    remove_column :users, :recovery_codes_digest, :text, array: true, default: [] if column_exists?(:users, :recovery_codes_digest)
  end
end
