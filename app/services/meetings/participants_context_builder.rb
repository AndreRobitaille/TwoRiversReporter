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

    def initialize(meeting)
      @meeting = meeting
    end

    def build
      committee = resolved_committee
      return "" unless committee

      agenda_names = roll_call_names
      roster_names = current_member_names(committee)
      names = agenda_names.any? ? agenda_names : roster_names
      <<~TEXT.squish
        Meeting participants: #{names.uniq.sort.join(", ")}.
      TEXT
    end

    private

    def resolved_committee
      Committee.resolve(@meeting.body_name) || fallback_committee
    end

    def fallback_committee
      body_name = @meeting.body_name.to_s
      return nil unless CITY_COUNCIL_VARIANTS.any? { |pattern| body_name.match?(pattern) }

      Committee.resolve("City Council")
    end

    def current_member_names(committee)
      committee.committee_memberships.current.includes(:member).map { |membership| membership.member.name }
    end

    def roll_call_names
      document_texts.flat_map { |text| extract_names_from_text(text) }.compact.map do |name|
        Member.normalize_name(name)
      end.reject(&:blank?)
    end

    def document_texts
      @meeting.meeting_documents.pluck(:extracted_text)
    end

    def extract_names_from_text(text)
      text.to_s.lines.flat_map do |line|
        next [] unless ROLL_CALL_LABELS.any? { |label| line.include?(label) }

        _, names = line.split(/Councilmembers:|Present:|Absent:|Absent and Excused:/, 2)
        next [] unless names

        names.split(/,| and /).map(&:strip)
      end
    end
  end
end
