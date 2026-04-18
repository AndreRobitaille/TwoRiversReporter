class AddAgendaStructureDigestToMeetings < ActiveRecord::Migration[7.1]
  def change
    add_column :meetings, :agenda_structure_digest, :string
  end
end
