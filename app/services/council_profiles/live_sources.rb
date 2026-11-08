module CouncilProfiles
  # Registered channels use the existing meeting/document discovery adapters.
  # Selecting a channel never widens the separately authorized historical window.
  class LiveSources
    TYPES = %w[minutes_pdf minutes_html packet_pdf].freeze
    # Minutes are already analyzed by the normal meeting/topic workflow.
    # A separate automatic request is only for explicitly selected packet
    # recommendations; minutes can still be selected for a bounded manual gap.
    EXTRACTION_TYPES = %w[packet_pdf].freeze

    def self.enabled?
      scope && (scope.fetch("document_types") & EXTRACTION_TYPES).any?
    end

    def self.documents
      policy = scope
      return MeetingDocument.none unless policy
      MeetingDocument.joins(:meeting).where(document_type: policy.fetch("document_types") & EXTRACTION_TYPES)
        .where(meetings: { committee_id: policy.fetch("committee_ids"),
          starts_at: Date.iso8601(policy.fetch("starting_on")).beginning_of_day..Time.current })
        .where.not(extracted_text: [ nil, "" ])
    end

    def self.scope
      month = CouncilAiBudgetMonth.find_by(budget_month: Date.current.beginning_of_month, revoked_at: nil)
      month&.live_actions&.fetch("issue_sources", nil)
    end
    private_class_method :scope
  end
end
