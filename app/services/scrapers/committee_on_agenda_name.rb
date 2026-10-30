module Scrapers
  # The Committee on Aging source at /bc-coa/ is titled "Committee On Agenda"
  # on the city site. Discovery copies listing titles into Meeting#body_name,
  # so correct that one slug before the title is stored, and rename rows that
  # already have it. Updates go through update_columns / update_all so meeting
  # and appearance callbacks cannot enqueue summarization or topic jobs.
  class CommitteeOnAgendaName
    SOURCE_SLUG = "bc-coa"
    CANONICAL_NAME = "Committee on Aging"
    ALIAS_NAME = "Committee On Agenda"
    MISLABELED_BODY = /\Acommittee\s+on\s+agenda\b/i
    MISLABELED_SQL = "^[[:space:]]*committee[[:space:]]+on[[:space:]]+agenda\\M"

    def self.correct(title, detail_url)
      text = title.to_s
      return text unless bc_coa_source?(detail_url) && mislabeled?(text)

      corrected_stored_name(text)
    end

    def self.bc_coa_source?(detail_url)
      path_segments(detail_url).any? { |segment| segment.casecmp?(SOURCE_SLUG) }
    end

    def self.mislabeled?(name)
      name.to_s.match?(MISLABELED_BODY)
    end

    def self.aging_title?(title)
      Meeting.normalized_body_name(title) == Meeting.normalized_body_name(CANONICAL_NAME)
    end

    def self.apply_to_existing_records!
      good = Committee.find_by(name: CANONICAL_NAME)
      bad = mislabeled_committee
      committees_merged = 0
      committees_renamed = 0

      if good && bad && good.id != bad.id
        merge_committee!(bad, good)
        committees_merged = 1
      elsif bad && good.nil?
        # Keep the existing slug so /committees/:slug does not change.
        bad.update_columns(name: CANONICAL_NAME, updated_at: Time.current)
        good = bad
        committees_renamed = 1
      end

      meetings = rename_meetings!(good)
      appearances = rename_appearances!(good)
      ensure_alias!(good)

      {
        meetings: meetings,
        topic_appearances: appearances,
        committees_merged: committees_merged,
        committees_renamed: committees_renamed
      }
    end

    def self.corrected_stored_name(name)
      name.to_s.sub(MISLABELED_BODY, CANONICAL_NAME)
    end

    def self.path_segments(detail_url)
      URI.parse(detail_url.to_s).path.to_s.split("/")
    rescue URI::InvalidURIError
      []
    end
    private_class_method :path_segments

    def self.mislabeled_committee
      Committee.where("btrim(name) ~* ?", MISLABELED_SQL).first
    end
    private_class_method :mislabeled_committee

    def self.rename_meetings!(committee)
      count = 0
      mislabeled_rows(Meeting).find_each do |meeting|
        next unless mislabeled?(meeting.body_name)

        attributes = { body_name: corrected_stored_name(meeting.body_name), updated_at: Time.current }
        attributes[:committee_id] = committee.id if committee && meeting.committee_id != committee.id
        meeting.update_columns(attributes)
        count += 1
      end
      count
    end
    private_class_method :rename_meetings!

    def self.rename_appearances!(committee)
      count = 0
      mislabeled_rows(TopicAppearance).find_each do |appearance|
        next unless mislabeled?(appearance.body_name)

        attributes = { body_name: corrected_stored_name(appearance.body_name), updated_at: Time.current }
        attributes[:committee_id] = committee.id if committee && appearance.committee_id != committee.id
        appearance.update_columns(attributes)
        count += 1
      end
      count
    end
    private_class_method :rename_appearances!

    def self.mislabeled_rows(model)
      model.where("btrim(body_name) ~* ?", MISLABELED_SQL)
    end
    private_class_method :mislabeled_rows

    def self.merge_committee!(bad, good)
      now = Time.current
      good_slug = good.slug
      bad_slug = bad.slug

      Meeting.where(committee_id: bad.id).update_all(committee_id: good.id, updated_at: now)
      TopicAppearance.where(committee_id: bad.id).update_all(committee_id: good.id, updated_at: now)
      move_aliases!(bad, good, now)
      move_memberships!(bad, good, now)
      bad.delete

      if bad_slug.present? && bad_slug != good.slug
        Redirect.upsert_redirect(
          source_path: "/committees/#{bad_slug}",
          destination: "/committees/#{good.slug}",
          status_code: 301
        )
      end

      good.reload
      return if good.slug == good_slug

      raise "Committee on Aging slug changed from #{good_slug} to #{good.slug}"
    end
    private_class_method :merge_committee!

    def self.move_aliases!(bad, good, now)
      CommitteeAlias.where(committee_id: bad.id).find_each do |record|
        if CommitteeAlias.where.not(id: record.id).exists?(name: record.name)
          record.delete
        else
          record.update_columns(committee_id: good.id, updated_at: now)
        end
      end
    end
    private_class_method :move_aliases!

    def self.move_memberships!(bad, good, now)
      CommitteeMembership.where(committee_id: bad.id).find_each do |membership|
        active_conflict = membership.ended_on.nil? && CommitteeMembership.where(
          committee_id: good.id,
          member_id: membership.member_id,
          ended_on: nil
        ).where.not(id: membership.id).exists?
        membership.update_columns(ended_on: Date.current, updated_at: now) if active_conflict
        membership.update_columns(committee_id: good.id, updated_at: now)
      end
    end
    private_class_method :move_memberships!

    def self.ensure_alias!(committee)
      return unless committee
      return if CommitteeAlias.exists?(name: ALIAS_NAME)

      CommitteeAlias.create!(committee: committee, name: ALIAS_NAME)
    end
    private_class_method :ensure_alias!
  end
end
