class AddResidentReportedContextToTopics < ActiveRecord::Migration[8.1]
  def change
    add_column :topics, :resident_reported_context, :jsonb, null: false, default: {}
  end
end
