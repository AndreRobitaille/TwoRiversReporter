class CreateMembershipApplications < ActiveRecord::Migration[8.1]
  def change
    create_table :membership_applications do |t|
      t.references :user, null: false, foreign_key: true
      t.string :first_name
      t.string :last_name
      t.string :street
      t.string :city
      t.string :state
      t.string :facebook_profile_url
      t.text :application_notes
      t.string :status, null: false, default: "email_pending"
      t.datetime :submitted_at
      t.datetime :reviewed_at
      t.references :reviewed_by, foreign_key: { to_table: :users }
      t.text :rejection_reason
      t.datetime :admin_notification_sent_at

      t.timestamps
    end

    add_index :membership_applications, :status
  end
end
