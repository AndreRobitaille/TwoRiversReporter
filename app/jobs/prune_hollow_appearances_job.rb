# Detaches hollow AgendaItemTopic rows after meeting summarization.
#
# A "hollow" appearance is one where the agenda item had no real civic
# activity — a standing update slot that the AI classified as a
# "status_update" with no vote, decision, or public hearing, and no
# linked motion. The typical offender is "SOLID WASTE UTILITY: UPDATES
# AND ACTION, AS NEEDED" — a monthly placeholder at Public Utilities
# Committee that rarely contains real decisions.
#
# Only operates on new-format summaries that have the `activity_level`
# field on at least one item_details entry. Old summaries are handled
# by the one-time backfill rake task (topics:prune_hollow_appearances).
#
# After pruning, demote_topic applies demotion rules based on remaining
# appearance count:
#   0 appearances → blocked + dormant (writes TopicStatusEvent audit row)
#   1 appearance  → dormant, still approved (writes TopicStatusEvent audit row)
#   2+ appearances → enqueues GenerateTopicBriefingJob to re-rate impact
#                    against the cleaned set (skipped if admin-locked)
class PruneHollowAppearancesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find_by(id: meeting_id)
    return unless meeting

    summary = meeting.meeting_summaries.order(created_at: :desc).first
    return unless summary&.generation_data.is_a?(Hash)

    item_details = summary.generation_data["item_details"]
    return unless item_details.is_a?(Array)

    new_format = item_details.any? { |e| e.is_a?(Hash) && e.key?("activity_level") }
    return unless new_format

    agenda_items = meeting.agenda_items.to_a
    entry_map = build_entry_map(agenda_items, item_details)

    affected_topic_ids = Set.new

    agenda_items.each do |ai|
      next unless hollow?(ai, entry_map[ai.id])

      AgendaItemTopic.where(agenda_item_id: ai.id).find_each do |ait|
        topic_id = ait.topic_id
        ait.destroy!
        TopicAppearance.where(topic_id: topic_id, agenda_item_id: ai.id).destroy_all
        affected_topic_ids << topic_id
      end
    end

    affected_topic_ids.each do |topic_id|
      topic = Topic.find_by(id: topic_id)
      next unless topic
      demote_topic(topic)
    end
  end

  private

  # Returns a hash mapping agenda_item_id => item_details entry (or nil).
  # Match by normalized title — drop leading numbering, trailing
  # "AS NEEDED" / "IF APPLICABLE", downcase, squish.
  def build_entry_map(agenda_items, item_details)
    normalized_entries = item_details.filter_map do |entry|
      next nil unless entry.is_a?(Hash)
      title = entry["agenda_item_title"]
      next nil unless title.is_a?(String)
      [ normalize_title(title), entry ]
    end

    agenda_items.each_with_object({}) do |ai, map|
      target = normalize_title(ai.title.to_s)
      # If two agenda items normalize to the same title (e.g., scraper
      # artifacts duplicating section headers), both map to the first
      # matching entry. The safe failure direction: neither gets
      # spuriously pruned. A real duplicate with real activity would
      # still be rescued by the Motion.exists? check in `hollow?`.
      match = normalized_entries.find { |norm, _e| norm == target }
      map[ai.id] = match&.last
    end
  end

  def normalize_title(title)
    return "" if title.nil? || title.strip.empty?
    title.to_s
      .gsub(/\A\s*\d+(-\d+)?[a-z]?\.?\s*/i, "")
      .gsub(/\s*,?\s*as needed\s*\z/i, "")
      .gsub(/\s*,?\s*if applicable\s*\z/i, "")
      .gsub(/\s+/, " ")
      .downcase
      .strip
  end

  def hollow?(agenda_item, entry)
    return false if Motion.where(agenda_item_id: agenda_item.id).exists?

    # Procedural filter: missing entry on a new-format summary means the
    # AI filtered this item as procedural — eligible for pruning.
    return true if entry.nil?

    entry["activity_level"] == "status_update" &&
      entry["vote"].nil? &&
      entry["decision"].nil? &&
      entry["public_hearing"].nil?
  end

  def demote_topic(topic)
    remaining = topic.topic_appearances.count

    case remaining
    when 0
      topic.update!(status: "blocked", lifecycle_status: "dormant")
      record_status_event(topic, lifecycle_status: "dormant",
                          notes: "Blocked — 0 appearances remaining after hollow-appearance pruning.")
    when 1
      topic.update!(lifecycle_status: "dormant")
      record_status_event(topic, lifecycle_status: "dormant",
                          notes: "Demoted — only 1 appearance remaining after hollow-appearance pruning.")
    else
      unless topic.resident_impact_admin_locked?
        Topics::GenerateTopicBriefingJob.perform_later(topic_id: topic.id)
      end
    end
  end

  def record_status_event(topic, lifecycle_status:, notes:)
    TopicStatusEvent.create!(
      topic: topic,
      lifecycle_status: lifecycle_status,
      occurred_at: Time.current,
      evidence_type: "hollow_appearance_prune",
      notes: notes
    )
  end
end
