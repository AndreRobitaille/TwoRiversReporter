class LinkHistoricalComparisonReservations < ActiveRecord::Migration[8.1]
  def change
    add_reference :campaign_action_requests, :council_history_request, foreign_key: true, index: { unique: true }
    change_column_null :campaign_action_requests, :council_ai_reservation_id, true
    add_check_constraint :campaign_action_requests,
      "num_nonnulls(council_ai_reservation_id, council_history_request_id) = 1", name: "one_campaign_action_reservation"
  end
end
