module CanonicalRosters
  class Synchronizer
    Change = Data.define(:action, :subject, :details)
    Result = Data.define(:changes) do
      def changed?
        changes.any?
      end
    end

    def initialize(snapshots:, dry_run: true, verified_at: Time.current)
      @snapshots = snapshots
      @dry_run = dry_run
      @verified_at = verified_at
      @changes = []
    end

    def call
      ActiveRecord::Base.transaction(requires_new: true) do
        snapshots.each do |snapshot|
          members_by_entry = resolve_members(snapshot.entries)
          sync_memberships(snapshot, members_by_entry) if snapshot.committee_name
          sync_positions(snapshot, members_by_entry) if snapshot.position_source
        end

        raise ActiveRecord::Rollback if dry_run
      end

      Result.new(changes: changes)
    end

    private

    attr_reader :snapshots, :dry_run, :verified_at, :changes

    def resolve_members(entries)
      entries.to_h do |entry|
        member = Member.resolve(entry.name)
        record_source_alias(member, entry.source_name) if entry.source_name != entry.name
        [ entry, member ]
      end
    end

    def record_source_alias(member, source_name)
      existing = MemberAlias.find_by(name: source_name)
      raise ArgumentError, "#{source_name} is already an alias for another member" if existing && existing.member_id != member.id

      MemberAlias.find_or_create_by!(member: member, name: source_name)
    end

    def sync_memberships(snapshot, members_by_entry)
      committee = Committee.find_by!(name: snapshot.committee_name)
      roster_entries = members_by_entry.select { |entry, _| entry.membership_role }
      roster_member_ids = roster_entries.values.map(&:id)

      roster_entries.each do |entry, member|
        membership = committee.committee_memberships.current.find_by(member: member)
        attributes = {
          role: entry.membership_role,
          position_title: entry.membership_title,
          source: snapshot.membership_source,
          source_url: snapshot.source_url,
          verified_at: verified_at
        }

        if membership
          update_membership(membership, attributes, committee, member)
        else
          committee.committee_memberships.create!(attributes.merge(member: member))
          changes << Change.new(
            action: "membership_created",
            subject: "#{committee.name} / #{member.name}",
            details: membership_description(attributes)
          )
        end
      end

      ending_candidates = committee.committee_memberships.current
        .where.not(source: "admin_manual")
        .where.not(member_id: roster_member_ids)
      ending_candidates = ending_candidates.where(role: [ nil, *snapshot.managed_roles ])

      ending_candidates
        .includes(:member)
        .find_each do |membership|
          membership.update!(ended_on: Date.current, verified_at: verified_at)
          changes << Change.new(
            action: "membership_ended",
            subject: "#{committee.name} / #{membership.member.name}",
            details: "absent from #{snapshot.source_url}"
          )
        end
    end

    def update_membership(membership, attributes, committee, member)
      return if membership.source == "admin_manual"

      semantic_attributes = attributes.except(:verified_at)
      changed_attributes = semantic_attributes.select { |key, value| membership.public_send(key) != value }

      if changed_attributes.empty?
        membership.update!(verified_at: verified_at)
        return
      end

      before = membership_description(membership.attributes.symbolize_keys)
      membership.update!(changed_attributes.merge(verified_at: verified_at))
      changes << Change.new(
        action: "membership_updated",
        subject: "#{committee.name} / #{member.name}",
        details: "#{before} -> #{membership_description(attributes)}"
      )
    end

    def sync_positions(snapshot, members_by_entry)
      position_entries = members_by_entry.select { |entry, _| entry.position_kind }

      position_entries.group_by { |entry, _| entry.position_kind }.each do |kind, grouped_entries|
        expected_member_ids = grouped_entries.map { |_, member| member.id }
        grouped_entries.each do |entry, member|
          sync_position(snapshot, entry, member)
        end

        MemberPosition.current
          .where(kind: kind)
          .where.not(source: "admin_manual")
          .where.not(member_id: expected_member_ids)
          .includes(:member)
          .find_each do |position|
            position.update!(ended_on: Date.current, verified_at: verified_at)
            changes << Change.new(
              action: "position_ended",
              subject: position.member.name,
              details: "#{position.title}; absent from #{snapshot.source_url}"
            )
          end
      end
    end

    def sync_position(snapshot, entry, member)
      position = member.member_positions.current.find_by(kind: entry.position_kind)
      attributes = {
        title: entry.position_title,
        source: snapshot.position_source,
        source_url: snapshot.source_url,
        verified_at: verified_at
      }

      if position.nil?
        member.member_positions.create!(
          attributes.merge(kind: entry.position_kind)
        )
        changes << Change.new(action: "position_created", subject: member.name, details: entry.position_title)
      elsif position.source == "admin_manual"
        nil
      elsif position.title != entry.position_title
        old_title = position.title
        position.update!(ended_on: Date.current, verified_at: verified_at)
        member.member_positions.create!(
          attributes.merge(kind: entry.position_kind)
        )
        changes << Change.new(
          action: "position_changed",
          subject: member.name,
          details: "#{old_title} -> #{entry.position_title}"
        )
      else
        changed_attributes = attributes.select { |key, value| position.public_send(key) != value }
        position.update!(changed_attributes) if changed_attributes.any?
      end
    end

    def membership_description(attributes)
      role_and_title = [ attributes[:role], attributes[:position_title] ].compact.join("; ")
      [ role_and_title, attributes[:source] ].compact.join(" from ")
    end
  end
end
