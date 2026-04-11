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
# field on at least one item_details entry.
#
# After pruning, demote_topic applies demotion rules based on remaining
# appearance count, recomputing last_activity_at in all cases so the
# homepage filter reflects the cleaned evidence set:
#   0 appearances → blocked + dormant, last_activity_at: nil (writes TopicStatusEvent)
#   1 appearance  → dormant, still approved, last_activity_at recomputed (writes TopicStatusEvent)
#   2+ appearances → last_activity_at recomputed; enqueues GenerateTopicBriefingJob
#                    to re-rate impact (skipped if admin-locked)
# Both 1-case and 2+-case enqueue GenerateTopicBriefingJob because without
# a re-rate, the homepage impact score reflects the stale pre-prune set.
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

    # After destroying hollow appearances, any TopicSummary for a
    # (topic, meeting) pair where no appearance remains is stale and
    # must be destroyed. Otherwise GenerateTopicBriefingJob keeps
    # feeding it as prior_meeting_analyses and the briefing regenerates
    # "appeared on the agenda" factual_record entries from pruned data.
    # If a topic has multiple appearances on the same meeting via
    # different agenda items and only some were pruned, the TopicSummary
    # must be preserved — use an existence check per (topic, meeting).
    affected_topic_ids.each do |topic_id|
      still_has_appearance = TopicAppearance
        .where(topic_id: topic_id, meeting_id: meeting.id)
        .exists?
      unless still_has_appearance
        TopicSummary.where(topic_id: topic_id, meeting_id: meeting.id).destroy_all
      end
    end

    affected_topic_ids.each do |topic_id|
      topic = Topic.find_by(id: topic_id)
      next unless topic
      demote_topic(topic, meeting_id)
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

  def demote_topic(topic, meeting_id)
    remaining = topic.topic_appearances.count
    new_last_activity = topic.topic_appearances.maximum(:appeared_at)

    Topic.transaction do
      case remaining
      when 0
        topic.update!(
          status: "blocked",
          lifecycle_status: "dormant",
          last_activity_at: nil
        )
        record_status_event(topic, lifecycle_status: "dormant",
                            notes: "Blocked — 0 appearances remaining after hollow-appearance pruning.")
      when 1
        topic.update!(
          lifecycle_status: "dormant",
          last_activity_at: new_last_activity
        )
        record_status_event(topic, lifecycle_status: "dormant",
                            notes: "Demoted — only 1 appearance remaining after hollow-appearance pruning.")
      else
        # 2+ remaining: recompute last_activity_at so homepage reflects the
        # cleaned appearance set (in case the most recent pruned appearance
        # was the one driving last_activity_at).
        topic.update!(last_activity_at: new_last_activity)
      end
    end

    # Enqueue briefing regeneration AFTER the transaction commits so job
    # dispatch only happens after a successful write. Runs for both the
    # 1-remaining and 2+-remaining cases — without recomputing impact, a
    # topic would stay at its pre-prune score and still surface on the
    # homepage. The 0-remaining case skips this because there's nothing
    # to brief about.
    if remaining >= 1 && !topic.resident_impact_admin_locked?
      Topics::GenerateTopicBriefingJob.perform_later(topic_id: topic.id, meeting_id: meeting_id)
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
