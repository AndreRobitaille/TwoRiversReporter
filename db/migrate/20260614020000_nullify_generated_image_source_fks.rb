class NullifyGeneratedImageSourceFks < ActiveRecord::Migration[8.1]
  def up
    remove_foreign_key :generated_images, :meeting_summaries, column: :source_summary_id
    remove_foreign_key :generated_images, :topic_briefings, column: :source_briefing_id

    add_foreign_key :generated_images, :meeting_summaries, column: :source_summary_id, on_delete: :nullify
    add_foreign_key :generated_images, :topic_briefings, column: :source_briefing_id, on_delete: :nullify
  end

  def down
    remove_foreign_key :generated_images, :meeting_summaries, column: :source_summary_id
    remove_foreign_key :generated_images, :topic_briefings, column: :source_briefing_id

    add_foreign_key :generated_images, :meeting_summaries, column: :source_summary_id
    add_foreign_key :generated_images, :topic_briefings, column: :source_briefing_id
  end
end
