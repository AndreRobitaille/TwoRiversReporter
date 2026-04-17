class AddAgendaItemStructureColumns < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:agenda_items, :kind)
      add_column :agenda_items, :kind, :string
    end

    add_index :agenda_items, :kind unless index_exists?(:agenda_items, :kind)

    unless column_exists?(:agenda_items, :parent_id)
      add_column :agenda_items, :parent_id, :bigint
    end

    add_index :agenda_items, :parent_id unless index_exists?(:agenda_items, :parent_id)
    add_foreign_key :agenda_items, :agenda_items, column: :parent_id unless foreign_key_exists?(:agenda_items, :agenda_items, column: :parent_id)
  end
end
