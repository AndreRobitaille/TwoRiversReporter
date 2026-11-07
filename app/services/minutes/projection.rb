module Minutes
  # Called only inside Publish's meeting/source transaction. Raw provider output
  # remains in MinutesExtraction; these rows are the current display projection.
  class Projection
    def initialize(meeting, input, votes, attendance)
      @meeting, @input, @votes, @attendance = meeting, input, votes, attendance
    end

    def call
      @meeting.meeting_attendances.destroy_all
      attendance_changed = create_attendance_records(@meeting, @attendance)
      @meeting.motions.destroy_all
      motions = normalize_motions(@votes.fetch("motions"), @input.text)
      motions.each do |data|
        motion = @meeting.motions.create!(description: data.fetch("description"), outcome: data["outcome"],
          agenda_item: resolve_agenda_item(data["agenda_item_ref"], @input.agenda_items))
        Array(data["votes"]).each do |vote|
          member = Member.resolve(vote["member"])
          next unless member
          value = vote.fetch("value").downcase
          existing = motion.votes.find_by(member: member)
          raise ArgumentError, "Conflicting votes for one member" if existing && existing.value != value
          motion.votes.create!(member: member, value: value, evidence_basis: "explicit") unless existing
        end
        add_absent_voting_members(motion, @meeting) if motion.votes.where.not(value: "absent").exists?
      end
      Committees::MembershipReconciler.call(@meeting.committee) if @meeting.committee_id.present?
      { "votes" => motions.any? ? "processed" : "empty", "attendance" => attendance_changed ? "processed" : "empty" }
    end

    private

    def normalize_motions(motions, minutes_text)
      motions.reject do |motion_data|
        unseconded_motion?(motion_data, minutes_text)
      end
    end

    def unseconded_motion?(motion_data, minutes_text)
      description = motion_data["description"].to_s.downcase
      return false unless description.include?("table")

      text = minutes_text.to_s.downcase.squish
      text.match?(/motion made by [^.]{0,80}\bto table\b[^.]{0,80}\b(no second|not seconded|lack of second)\b/)
    end

    def add_absent_voting_members(motion, meeting)
      existing_member_ids = motion.votes.pluck(:member_id)
      absent_members = meeting.meeting_attendances
        .voting_members
        .where(status: %w[absent excused])
        .where.not(member_id: existing_member_ids)
        .includes(:member)
        .map(&:member)

      absent_members.each do |member|
        Vote.create!(motion: motion, member: member, value: "absent", evidence_basis: "attendance_derived")
      end
    end

    # Resolve the AI's agenda_item_ref to a real AgendaItem record.
    #
    # Strategy: fuzzy title match FIRST. Number match is only a fallback for
    # bare refs like "7a" where there's no title text. This ordering matters —
    # when the AI returns a multi-line ref that includes a parent section
    # header plus a sub-item ("7.: ACTION ITEMS\nA.: 26-045 Resolution..."),
    # number-first matching extracts "7." and binds to the section header
    # (2-word title) instead of the specific sub-item (14-word title).
    # Fuzzy-first naturally prefers the content-rich specific match.
    def resolve_agenda_item(ref, agenda_items)
      return nil if ref.blank?

      # Fuzzy title match (word overlap)
      ref_words = ref.downcase.gsub(/[^a-z0-9\s]/, "").split
      return nil if ref_words.empty?

      best_match = nil
      best_score = 0.0

      agenda_items.each do |item|
        item_word_sets = [ item.title, item.try(:display_context_title) ].compact.filter_map do |text|
          words = text.downcase.gsub(/[^a-z0-9\s]/, "").split
          words unless words.empty?
        end
        next if item_word_sets.empty?

        score = item_word_sets.map { |item_words|
          overlap = (ref_words & item_words).size
          overlap.to_f / [ ref_words.size, item_words.size ].max
        }.max || 0.0

        if score > best_score
          best_score = score
          best_match = item
        end
      end

      return best_match if best_score >= 0.5

      # Fall back to exact item-number match (handles bare refs like "7a" with
      # no title text). Uses the first token before space or colon.
      number_match = ref.match(/\A(\S+?)(?:[\s:]|\z)/i)
      if number_match
        candidate = number_match[1]
        by_number = agenda_items.find { |item| item.number&.downcase == candidate.downcase }
        return by_number if by_number
      end

      nil
    end

    def create_attendance_records(meeting, data)
      created = false
      (data["voting_members_present"] || []).each do |name|
        next if name.blank?

        member = Member.resolve(name)
        next unless member
        next if meeting.meeting_attendances.exists?(member: member)

        meeting.meeting_attendances.create!(
          member: member, status: "present", attendee_type: "voting_member"
        )
        created = true
      end

      (data["voting_members_absent"] || []).each do |name|
        next if name.blank?

        member = Member.resolve(name)
        next unless member
        next if meeting.meeting_attendances.exists?(member: member)

        meeting.meeting_attendances.create!(
          member: member, status: "absent", attendee_type: "voting_member"
        )
        created = true
      end

      (data["non_voting_staff"] || []).each do |entry|
        name = entry.is_a?(Hash) ? entry["name"] : entry
        next if name.blank?

        member = Member.resolve(name)
        next unless member
        next if meeting.meeting_attendances.exists?(member: member)

        meeting.meeting_attendances.create!(
          member: member, status: "present", attendee_type: "non_voting_staff",
          capacity: entry.is_a?(Hash) ? entry["capacity"] : nil
        )
        created = true
      end

      (data["guests"] || []).each do |entry|
        name = entry.is_a?(Hash) ? entry["name"] : entry
        next if name.blank?

        member = Member.resolve(name)
        next unless member
        next if meeting.meeting_attendances.exists?(member: member)

        meeting.meeting_attendances.create!(
          member: member, status: "present", attendee_type: "guest"
        )
        created = true
      end

      created
    end
  end
end
