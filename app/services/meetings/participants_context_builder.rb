module Meetings
  class ParticipantsContextBuilder
    ROLL_CALL_LABELS = [
      "Councilmembers:",
      "Present:",
      "Absent:",
      "Absent and Excused:"
    ].freeze

    def initialize(meeting)
      @meeting = meeting
    end

    def build
      committee = resolved_committee
      return [] unless committee

      agenda_names = roll_call_names
      roster_names = current_member_names(committee)
      names = agenda_names.any? ? agenda_names : roster_names
      names.uniq.sort
    end

    private

    def resolved_committee
      Committee.resolve(@meeting.body_name) || fallback_committee
    end

    def fallback_committee
      body_name = @meeting.body_name.to_s
      return nil unless body_name.match?(/council/i)

      Committee.resolve("City Council")
    end

    def current_member_names(committee)
      committee.committee_memberships.current.includes(:member).map { |membership| membership.member.name }
    end

    def roll_call_names
      document_texts.filter_map { |text| extract_names_from_text(text) }.flatten.compact.map do |name|
        Member.normalize_name(name)
      end.reject(&:blank?)
    end

    def document_texts
      @meeting.meeting_documents.pluck(:extracted_text)
    end

    def extract_names_from_text(text)
      line = text.to_s.lines.find { |l| ROLL_CALL_LABELS.any? { |label| l.include?(label) } }
      return [] unless line

      _, names = line.split(/Councilmembers:|Present:|Absent:|Absent and Excused:/, 2)
      return [] unless names

      names.split(/,| and /).map(&:strip)
    end
  end
end
