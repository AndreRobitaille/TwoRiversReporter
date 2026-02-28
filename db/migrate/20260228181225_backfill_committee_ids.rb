class BackfillCommitteeIds < ActiveRecord::Migration[8.1]
  def up
    # Backfill meetings
    Meeting.find_each do |meeting|
      next if meeting.committee_id.present? || meeting.body_name.blank?
      committee = Committee.resolve(meeting.body_name)
      meeting.update_column(:committee_id, committee.id) if committee
    end

    # Backfill topic_appearances from their meetings
    TopicAppearance.includes(:meeting).find_each do |appearance|
      next if appearance.committee_id.present?
      if appearance.meeting&.committee_id.present?
        appearance.update_column(:committee_id, appearance.meeting.committee_id)
      elsif appearance.body_name.present?
        committee = Committee.resolve(appearance.body_name)
        appearance.update_column(:committee_id, committee.id) if committee
      end
    end
  end

  def down
    Meeting.update_all(committee_id: nil)
    TopicAppearance.update_all(committee_id: nil)
  end
end
