module Topics
  class ResidentImpactPolicy
    POLICY_WINDOW = 30.days
    SEX_OFFENDER_PATTERN = /\bsex(?:ual)?[\s-]+offenders?\b/i
    LAW_SCOPE_PATTERN = /\b(city[\s-]?wide|ordinance|municipal code)\b/i
    LAW_CHANGE_PATTERN = /\b(amend(?:ment|ments|ed|ing|s)?|repeal(?:ed|ing|s)?|recreat(?:e|ed|ing|es)|replac(?:e|ed|ing|es)|rewrit(?:e|ing|es)|revis(?:e|ed|ing|es|ion))\b/i
    INDIVIDUAL_RELIEF_PATTERN = /\b(?:consider|review|hear)\b.*\b(?:appeal|variance|waiver|exemption|relief)\b/i
    CITYWIDE_PROHIBITION_REPLACEMENT_PATTERN = /\b(?:replac(?:e|es|ed|ing)|repeal(?:s|ed|ing)?)\s+(?:(?:the|a|current|existing)\s+)*city[\s-]?wide\s+(?:(?:sex[\s-]+offender|residency|residence)\s+)*(?:ban|prohibition)\b/i

    def initialize(topic)
      @topic = topic
    end

    def self.sex_offender_text?(text)
      text.to_s.match?(SEX_OFFENDER_PATTERN)
    end

    def sex_offender_topic?
      self.class.sex_offender_text?(@topic.name) || agenda_entries.any? { |title, _starts_at, _status| self.class.sex_offender_text?(title) }
    end

    def minimum_score
      return unless sex_offender_topic?

      agenda_entries.filter_map do |title, starts_at, status|
        next unless starts_at && starts_at > POLICY_WINDOW.ago
        next if status == "cancelled"
        next unless self.class.sex_offender_text?(title)
        next if title.match?(INDIVIDUAL_RELIEF_PATTERN)
        next unless title.match?(LAW_SCOPE_PATTERN) && title.match?(LAW_CHANGE_PATTERN)

        title.match?(CITYWIDE_PROHIBITION_REPLACEMENT_PATTERN) ? 5 : 4
      end.max || 3
    end

    private

    def agenda_entries
      @agenda_entries ||= @topic.agenda_items.substantive.joins(:meeting).pluck(:title, "meetings.starts_at", "meetings.status")
    end
  end
end
