class AddMeetingIdToKnowledgeSources < ActiveRecord::Migration[8.1]
  def change
    add_reference :knowledge_sources, :meeting, null: true, foreign_key: true
  end
end
