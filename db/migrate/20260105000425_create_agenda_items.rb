class CreateAgendaItems < ActiveRecord::Migration[8.1]
  def change
    create_table :agenda_items do |t|
      t.references :meeting, null: false, foreign_key: true
      t.string :number
      t.text :title
      t.text :summary
      t.text :recommended_action
      t.integer :order_index

      t.timestamps
    end
  end
end
