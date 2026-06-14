module GeneratedImages
  class MeetingEligibility
    Result = Data.define(:eligible?, :reason, :primary_text, :composite?)

    WEAK_PATTERNS = /\b(call to order|roll call|approval of minutes|adjourn|reports?|updates?|routine|no assessment appeals|reschedule|discussed|discussing|discussion|talked about|reviewed)\b/i
    ACTION_PATTERNS = /\b(vote|approved|denied|contract|tax|levy|assessment|shutoff|rezon|ordinance|budget|grant|hearing|development|policy|funding|rate|fee|permit|rejected|adopted|authorized|awarded|ordered|purchased|constructed|changed|increased|decreased|set|ratified|passed|tabled|referred|amended|bond|borrow|repair|replace|install|approve|deny|award|award(ed)?|commit|commitment)\b/i
    DOMAIN_PATTERNS = /\b(utility|utilities|sewer|water|street|streets|sidewalk|sidewalks|road|roads|drainage|stormwater|wastewater|electric|power)\b/i

    def initialize(meeting, summary: nil)
      @meeting = meeting
      @summary = summary || preferred_summary
    end

    def call
      return Result.new(false, "missing summary", nil, false) unless @summary

      candidates = candidate_texts
      substantive_candidates = candidates.select { |text| substantive?(text) }
      primary = substantive_candidates.first

      return Result.new(false, "no substantive visual hook", nil, false) unless primary

      Result.new(true, nil, primary, substantive_candidates.size >= 3)
    end

    private

    def preferred_summary
      summaries = @meeting.meeting_summaries.to_a.sort_by do |summary|
        [ summary_priority(summary), -(summary.updated_at || Time.at(0)).to_i ]
      end

      summaries.find { |summary| usable_summary?(summary) }
    end

    def candidate_texts
      gd = @summary.generation_data || {}
      highlights = Array(gd["highlights"]).map { |h| h["text"].to_s }
      item_texts = Array(gd["item_details"]).flat_map do |item|
        [ item["agenda_item_title"], item["summary"], item["decision"] ].compact.map(&:to_s)
      end
      [ gd["headline"].to_s, *highlights, *item_texts, fallback_content ].map(&:strip).reject(&:blank?)
    end

    def substantive?(text)
      return false if text.length < 40
      return false if text.match?(WEAK_PATTERNS) && !text.match?(ACTION_PATTERNS)
      return false unless text.match?(ACTION_PATTERNS)

      if text.match?(DOMAIN_PATTERNS)
        return true if text.match?(ACTION_PATTERNS) && !text.match?(WEAK_PATTERNS)
        return false
      end

      true
    end

    def fallback_content
      @summary.content.to_s
    end

    def summary_priority(summary)
      %w[minutes_recap transcript_recap packet_analysis agenda_preview].index(summary.summary_type) || 99
    end

    def usable_summary?(summary)
      summary.generation_data.present? || summary.content.present?
    end
  end
end
