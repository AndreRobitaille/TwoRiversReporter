class CreateAgendaItemTopics < ActiveRecord::Migration[8.1]
  def change
    create_table :agenda_item_topics do |t|
      t.references :agenda_item, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true

      t.timestamps
    end
  end
end
