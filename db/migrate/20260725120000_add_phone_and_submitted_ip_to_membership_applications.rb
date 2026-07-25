class AddPhoneAndSubmittedIpToMembershipApplications < ActiveRecord::Migration[8.1]
  # Both columns are nullable with no default and no index, so Postgres adds
  # them with a catalog-only change — no table rewrite, no lock held while
  # existing rows are read. Safe to run against the live application table.
  def change
    add_column :membership_applications, :phone, :string
    add_column :membership_applications, :submitted_ip, :string
  end
end
