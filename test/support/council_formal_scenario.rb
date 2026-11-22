require_relative "council_issue_scenario"

module CouncilFormalScenario
  include CouncilIssueScenario

  def setup_formal_records
    setup_issue_updates
    @editor = User.create!(email_address: "formal-editor@example.test", admin: true, status: "active")
    @editor.passkey_credentials.create!(external_id: "formal-editor-key", public_key: "public-key", sign_count: 0)
    @filing_quote = "On June 2, 2025, a formal complaint alleging misuse of equipment was filed against Jordan Attendance and Taylor Issue. These are allegations, not findings."
    @formal_source = CouncilFormalSource.create!(formal_attributes)
    clear_enqueued_jobs
  end

  def formal_attributes
    { title: "Synthetic equipment-use complaint", case_reference: "SYNTHETIC-2025-1", reviewing_body: "Synthetic Review Board",
      policy_label: "Synthetic conduct policy, 2025 version", source_url: "https://example.test/formal-complaint.pdf", record_kind: "complaint",
      published_on: "2025-06-03", permitted_text: @filing_quote, subject_names: [ @member.name, @peer.name ],
      service_period_keys: [ @period.period_key ], verified_by: @editor, verified_at: Time.current,
      private_notes: "PRIVATE COMPLAINANT CANARY, 99 Hidden Street, private@example.test" }
  end

  def formal_response(kind: "filed", date: "2025-06-02", quote: @filing_quote, subjects: [ @member.name, @peer.name ])
    { complete: true, formal_record: true, events: [ { kind: kind, occurred_on: date, subjects: subjects, quote: quote } ] }
  end

  def extract_formal(source = @formal_source, data: formal_response)
    stage = CouncilProfiles::ExtractFormalRecords.prepare(source)
    with_campaign_transport(content: data.to_json) do
      ExtractCouncilFormalRecordsJob.perform_now(source.id, budget_run_id: campaign_budget(stage: stage).id)
    end
    stage.reload
  end
end
