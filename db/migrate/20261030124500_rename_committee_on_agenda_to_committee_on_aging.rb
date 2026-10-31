class RenameCommitteeOnAgendaToCommitteeOnAging < ActiveRecord::Migration[8.1]
  CANONICAL_NAME = "Committee on Aging"
  MISLABELED_NAME = /\Acommittee\s+on\s+agenda\b/i
  MISLABELED_SQL = "^[[:space:]]*committee[[:space:]]+on[[:space:]]+agenda\\M"
  SOURCE_SLUG = "bc-coa"

  class MeetingRow < ActiveRecord::Base
    self.table_name = "meetings"
  end

  class CommitteeRow < ActiveRecord::Base
    self.table_name = "committees"
  end

  class AliasRow < ActiveRecord::Base
    self.table_name = "committee_aliases"
  end

  class MembershipRow < ActiveRecord::Base
    self.table_name = "committee_memberships"
  end

  class AppearanceRow < ActiveRecord::Base
    self.table_name = "topic_appearances"
  end

  class RedirectRow < ActiveRecord::Base
    self.table_name = "redirects"
  end

  def up
    meetings = mislabeled_meetings
    return if meetings.empty?

    good = CommitteeRow.where(name: CANONICAL_NAME).order(:id).first
    bad = mislabeled_committee(meetings)

    # Same leftover-reference rule as merge_committee!: an in-place rename is safe
    # only when every meeting and appearance that points at this committee is one
    # we are about to correct. Anything else stays on the old row.
    if good.nil? && bad && !outside_references?(bad, ignoring_meeting_ids: meetings.map(&:id))
      bad.update_columns(name: CANONICAL_NAME, updated_at: Time.current)
      good = CommitteeRow.find(bad.id)
    end
    good ||= CommitteeRow.create!(name: CANONICAL_NAME, slug: "committee-on-aging")
    distinct_bad = bad if bad && good.id != bad.id

    meeting_ids = rename_meetings!(meetings, good)
    appearance_count = rename_appearances!(meeting_ids, good, distinct_bad&.id)
    merged = distinct_bad ? merge_committee!(distinct_bad, good) : false
    remove_aging_alias!(good)

    say "Renamed Committee On Agenda records: #{ { meetings: meeting_ids.size, topic_appearances: appearance_count, committees_merged: merged ? 1 : 0 }.inspect }"
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
      "Older Committee on Aging meetings already use that name; restore a reviewed row explicitly instead"
  end

  private

  def mislabeled_committee(meetings)
    CommitteeRow.where(id: meetings.map(&:committee_id)).where(
      "btrim(name) ~* ?", "^committee[[:space:]]+on[[:space:]]+agenda$"
    ).order(:id).first
  end

  # After the corrected meetings are moved, merge refuses when any meeting or
  # appearance still points at the old committee. The rename-only path asks the
  # same question before the move by ignoring the meetings it is about to correct.
  def outside_references?(committee, ignoring_meeting_ids: [])
    meetings = MeetingRow.where(committee_id: committee.id)
    meetings = meetings.where.not(id: ignoring_meeting_ids) if ignoring_meeting_ids.any?
    return true if meetings.exists?

    appearances = AppearanceRow.where(committee_id: committee.id)
    if ignoring_meeting_ids.any?
      appearances = appearances.where(
        "meeting_id IS NULL OR meeting_id NOT IN (?)",
        ignoring_meeting_ids
      )
    end
    appearances.exists?
  end

  def mislabeled_meetings
    MeetingRow.where("btrim(body_name) ~* ?", MISLABELED_SQL)
      .where("detail_page_url ILIKE ?", "%#{SOURCE_SLUG}%").order(:id).select do |meeting|
        mislabeled_name?(meeting.body_name) && bc_coa_url?(meeting.detail_page_url)
      end
  end

  def rename_meetings!(meetings, committee)
    meetings.each do |meeting|
      meeting.update_columns(body_name: corrected_name(meeting.body_name), committee_id: committee.id, updated_at: Time.current)
    end
    meetings.map(&:id)
  end

  def rename_appearances!(meeting_ids, committee, bad_committee_id)
    return 0 if meeting_ids.empty?

    count = 0
    AppearanceRow.where(meeting_id: meeting_ids).find_each do |appearance|
      attributes = {}
      if mislabeled_name?(appearance.body_name)
        attributes[:body_name] = corrected_name(appearance.body_name)
      end
      relink_bad_committee = bad_committee_id.present? && appearance.committee_id == bad_committee_id
      if committee && appearance.committee_id != committee.id && (mislabeled_name?(appearance.body_name) || relink_bad_committee)
        attributes[:committee_id] = committee.id
      end
      next if attributes.empty?

      attributes[:updated_at] = Time.current
      appearance.update_columns(attributes)
      count += 1 if attributes[:body_name]
    end
    count
  end

  def merge_committee!(bad, good)
    if outside_references?(bad)
      say "Left committee #{bad.id} (#{bad.slug}) in place because rows outside /bc-coa/ still reference it"
      return false
    end

    good_slug = good.slug
    bad_slug = bad.slug
    now = Time.current
    move_aliases!(bad, good, now)
    move_memberships!(bad, good, now)
    bad.delete
    write_redirect(bad_slug, good_slug, now) if bad_slug.present? && bad_slug != good_slug

    good.reload
    raise "Committee on Aging slug changed from #{good_slug} to #{good.slug}" if good.slug != good_slug

    true
  end

  def move_aliases!(bad, good, now)
    AliasRow.where(committee_id: bad.id).order(:id).find_each do |record|
      if AliasRow.where.not(id: record.id).exists?(name: record.name)
        record.delete
      else
        record.update_columns(committee_id: good.id, updated_at: now)
      end
    end
  end

  def move_memberships!(bad, good, now)
    MembershipRow.where(committee_id: bad.id).order(:id).find_each do |membership|
      active_duplicate = membership.ended_on.nil? && MembershipRow.find_by(
        committee_id: good.id,
        member_id: membership.member_id,
        ended_on: nil
      )
      if active_duplicate
        identity_columns = %w[id committee_id created_at updated_at]
        unless membership.attributes.except(*identity_columns) == active_duplicate.attributes.except(*identity_columns)
          raise "Conflicting active committee memberships #{membership.id} and #{active_duplicate.id}; review their roles and source authority before merging"
        end

        membership.delete
      else
        membership.update_columns(committee_id: good.id, updated_at: now)
      end
    end
  end

  def remove_aging_alias!(committee)
    return unless committee

    AliasRow.where(committee_id: committee.id, name: "Committee On Agenda").delete_all
  end

  def write_redirect(bad_slug, good_slug, now)
    source_path = "/committees/#{bad_slug}"
    destination = "/committees/#{good_slug}"
    existing = RedirectRow.find_by(source_path: source_path)
    if existing
      existing.update_columns(destination: destination, status_code: 301, updated_at: now)
    else
      RedirectRow.insert({
        source_path: source_path,
        destination: destination,
        status_code: 301,
        hits: 0,
        created_at: now,
        updated_at: now
      })
    end
    # A request before commit can repopulate the map with the old rows.
    # Match Redirect's after_commit timing even though these writes skip callbacks.
    ActiveRecord.after_all_transactions_commit { Rails.cache.delete(Redirect::CACHE_KEY) }
  end

  def mislabeled_name?(name)
    name.to_s.match?(MISLABELED_NAME)
  end

  def corrected_name(name)
    name.to_s.sub(MISLABELED_NAME, CANONICAL_NAME)
  end

  def bc_coa_url?(detail_url)
    URI.parse(detail_url.to_s).path.to_s.split("/").any? { |segment| segment.casecmp?(SOURCE_SLUG) }
  rescue URI::InvalidURIError
    false
  end
end
