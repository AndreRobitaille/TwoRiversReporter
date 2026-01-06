class AddOcrStatusToMeetingDocuments < ActiveRecord::Migration[8.1]
  def change
    add_column :meeting_documents, :ocr_status, :string
  end
end
