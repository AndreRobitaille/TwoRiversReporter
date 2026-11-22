class KeyCouncilTermSummariesByServiceStart < ActiveRecord::Migration[8.1]
  def up
    rename_column :council_term_summaries, :election_on, :term_started_on
    execute <<~SQL
      UPDATE council_term_summaries AS summaries SET term_started_on = periods.started_on
      FROM council_service_periods AS periods
      WHERE periods.member_id = summaries.member_id
        AND periods.started_on = (SELECT MAX(started_on) FROM council_service_periods
          WHERE member_id = summaries.member_id AND started_on < summaries.term_started_on
            AND started_on <= COALESCE(summaries.generated_at::date, CURRENT_DATE))
    SQL
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "A service start does not identify a future election"
  end
end
