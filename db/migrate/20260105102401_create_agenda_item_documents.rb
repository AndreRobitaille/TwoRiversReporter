class CreateAgendaItemDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :agenda_item_documents do |t|
      t.references :agenda_item, null: false, foreign_key: true
      t.references :meeting_document, null: false, foreign_key: true

      t.timestamps
    end
  end
end
