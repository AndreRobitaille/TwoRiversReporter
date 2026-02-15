class AgendaItemTopic < ApplicationRecord
  belongs_to :agenda_item
  belongs_to :topic

  after_create :create_appearance_and_update_continuity

  private

  def create_appearance_and_update_continuity
    # Create Appearance if it doesn't exist
    unless TopicAppearance.exists?(topic: topic, agenda_item: agenda_item)
      meeting = agenda_item.meeting
      TopicAppearance.create!(
        topic: topic,
        meeting: meeting,
        agenda_item: agenda_item,
        appeared_at: meeting.starts_at || agenda_item.created_at,
        body_name: meeting.body_name,
        evidence_type: "agenda_item",
        source_ref: { agenda_item_id: agenda_item.id, title: agenda_item.title }
      )
    end

    # Trigger Continuity Update
    Topics::UpdateContinuityJob.perform_later(topic_id: topic.id)
  end
end
