class AddMetadataToMeetingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_documents, :etag, :string
    add_column :meeting_documents, :last_modified, :datetime
    add_column :meeting_documents, :content_length, :bigint
  end
end
