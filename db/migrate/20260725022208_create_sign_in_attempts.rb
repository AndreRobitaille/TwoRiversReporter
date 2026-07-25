class CreateSignInAttempts < ActiveRecord::Migration[8.1]
  def change
    create_table :sign_in_attempts do |t|
      t.string :email_address, null: false
      t.timestamps
    end

    add_index :sign_in_attempts, [ :email_address, :created_at ]
  end
end
