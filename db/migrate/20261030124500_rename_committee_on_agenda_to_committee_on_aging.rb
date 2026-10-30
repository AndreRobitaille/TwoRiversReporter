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
    good = CommitteeRow.where(name: CANONICAL_NAME).order(:id).first
    bad = mislabeled_committee
    distinct_bad = good && bad && good.id != bad.id ? bad : nil

    if bad && good.nil?
      bad.update_columns(name: CANONICAL_NAME, updated_at: Time.current)
      good = CommitteeRow.find(bad.id)
    end

    meeting_ids = rename_meetings!(good)
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

  def mislabeled_committee
    CommitteeRow.where("btrim(name) ~* ?", MISLABELED_SQL).order(:id).first
  end

  def rename_meetings!(committee)
    ids = []
    MeetingRow.where("btrim(body_name) ~* ?", MISLABELED_SQL).where("detail_page_url ILIKE ?", "%#{SOURCE_SLUG}%").find_each do |meeting|
      next unless mislabeled_name?(meeting.body_name) && bc_coa_url?(meeting.detail_page_url)

      attributes = { body_name: corrected_name(meeting.body_name), updated_at: Time.current }
      attributes[:committee_id] = committee.id if committee && meeting.committee_id != committee.id
      meeting.update_columns(attributes)
      ids << meeting.id
    end
    ids
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
    if MeetingRow.where(committee_id: bad.id).exists? || AppearanceRow.where(committee_id: bad.id).exists?
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
      active_duplicate = membership.ended_on.nil? && MembershipRow.where(
        committee_id: good.id,
        member_id: membership.member_id,
        ended_on: nil
      ).where.not(id: membership.id).exists?
      if active_duplicate
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
