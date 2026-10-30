class RenameCommitteeOnAgendaToCommitteeOnAging < ActiveRecord::Migration[8.1]
  def up
    counts = Scrapers::CommitteeOnAgendaName.apply_to_existing_records!
    say "Renamed Committee On Agenda records: #{counts.inspect}"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Older Committee on Aging meetings already use that name; restore a reviewed row explicitly instead"
  end
end
