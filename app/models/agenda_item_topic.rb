class AgendaItemTopic < ApplicationRecord
  belongs_to :agenda_item
  belongs_to :topic

  after_create :create_appearance_and_update_continuity

  private

  def create_appearance_and_update_continuity
    # Create the appearance idempotently. The previous `unless exists?` +
    # `create!` sequence was racy — two concurrent AgendaItemTopic creations
    # for the same (topic, agenda_item) could both pass the exists? check
    # before either inserted, producing duplicate TopicAppearance rows.
    #
    # Now relies on the unique DB index on (topic_id, meeting_id,
    # agenda_item_id) and swallows ActiveRecord::RecordNotUnique /
    # RecordInvalid, which the concurrent second writer will hit.
    meeting = agenda_item.meeting
    begin
      TopicAppearance.create!(
        topic: topic,
        meeting: meeting,
        agenda_item: agenda_item,
        appeared_at: meeting.starts_at || agenda_item.created_at,
        body_name: meeting.body_name,
        committee: meeting.committee,
        evidence_type: "agenda_item",
        source_ref: { agenda_item_id: agenda_item.id, title: agenda_item.title }
      )
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Already exists — another writer raced us. Safe to ignore.
    end

    # Trigger Continuity Update
    Topics::UpdateContinuityJob.perform_later(topic_id: topic.id)

    # Trigger headline briefing for future meetings
    if agenda_item.meeting.starts_at&.future?
      Topics::UpdateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: agenda_item.meeting.id,
        tier: "headline_only"
      )
    end
  end
end
