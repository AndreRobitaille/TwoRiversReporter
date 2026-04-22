module Meetings
  class ParticipantsContextBuilder
    ROLL_CALL_LABELS = [
      "Councilmembers:",
      "Present:",
      "Absent:",
      "Absent and Excused:"
    ].freeze

    CITY_COUNCIL_VARIANTS = [
      /\bcity council reorganizational meeting\b/i,
      /\bcity council\b/i
    ].freeze

    def initialize(meeting, agenda_text = nil)
      @meeting = meeting
      @agenda_text = agenda_text
    end

    def build
      committee = resolved_committee
      return "" unless committee

      agenda_names = roll_call_names
      roster_names = current_member_names(committee)
      <<~TEXT.squish
        Canonical roster: #{roster_names.uniq.sort.join(", ")}.
        Meeting roll call: #{agenda_names.any? ? agenda_names.uniq.sort.join(", ") : "none"}.
      TEXT
    end

    private

    def resolved_committee
      @meeting.committee || Committee.resolve(@meeting.body_name) || fallback_committee
    end

    def fallback_committee
      body_name = @meeting.body_name.to_s
      return nil unless CITY_COUNCIL_VARIANTS.any? { |pattern| body_name.match?(pattern) }

      Committee.resolve("City Council")
    end

    def current_member_names(committee)
      meeting_date = @meeting.starts_at&.to_date || Date.current

      committee.committee_memberships
        .includes(:member)
        .select { |membership| membership_active_on?(membership, meeting_date) && !%w[staff non_voting].include?(membership.role) }
        .map { |membership| membership.member.name }
    end

    def roll_call_names
      document_texts.flat_map { |text| extract_names_from_text(text) }.compact.map do |name|
        Member.normalize_name(name)
      end.reject(&:blank?)
    end

    def document_texts
      @agenda_text ? [ @agenda_text ] : []
    end

    def extract_names_from_text(text)
      text.to_s.lines.flat_map do |line|
        next [] unless line.match?(/^\s*(Councilmembers|Present|Absent|Absent and Excused):\s*/i)

        _, names = line.split(/Councilmembers:|Present:|Absent:|Absent and Excused:/, 2)
        next [] unless names

        names.split(/,| and /).map(&:strip)
      end
    end

    def membership_active_on?(membership, meeting_date)
      started_on = membership.started_on || Date.new(1900, 1, 1)
      ended_on = membership.ended_on || Date.new(9999, 12, 31)

      started_on <= meeting_date && ended_on >= meeting_date
    end
  end
end
