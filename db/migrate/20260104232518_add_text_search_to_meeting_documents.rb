class AddTextSearchToMeetingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_documents, :extracted_text, :text
    add_column :meeting_documents, :search_vector, :tsvector
    add_index :meeting_documents, :search_vector, using: :gin
  end
end
