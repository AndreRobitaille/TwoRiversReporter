require "application_system_test_case"

class KnowledgeWithdrawalJourneyTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "admin sees withdrawn evidence and reingest cannot restore it" do
    admin = User.create!(email_address: "synthetic-knowledge-admin@example.test", status: "active", admin: true)
    admin.passkey_credentials.create!(external_id: "synthetic-knowledge-key", public_key: "fixture", sign_count: 0)
    sign_in_by_email(admin)
    click_link "Admin", exact: true
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/knowledge-browser")
    summary = meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: { headline: "Synthetic supporting record" })
    source = KnowledgeSource.create!(title: "Synthetic knowledge record", body: "Synthetic retained background", source_type: "note",
      origin: "extracted", status: "approved", active: true, reasoning: "Synthetic source evidence",
      meeting: meeting, source_summary: summary, source_summary_manifest: Knowledge::SummaryEvidence.capture(summary))
    within "#admin-sidebar" do
      click_link "Knowledge Sources", exact: true
    end
    click_link source.title, exact: true
    assert_current_path admin_knowledge_source_path(source)
    assert_text source.body
    assert_no_text /Evidence withdrawn/i
    clear_enqueued_jobs
    assert_enqueued_with(job: IngestKnowledgeSourceJob, args: [ source.id ]) do
      click_button "Re-ingest", exact: true
      assert_text "Re-ingestion queued."
    end
    embedding = Object.new
    embedding.define_singleton_method(:embed) { |_| [ 1.0, 0.0, 0.0 ] }
    Ai::EmbeddingService.stub(:new, embedding) { perform_enqueued_jobs(only: IngestKnowledgeSourceJob) }
    chunks = source.knowledge_chunks.order(:id).map(&:attributes)
    assert_equal 1, chunks.size

    summary.update!(evidence_withdrawn_at: Time.current)
    visit current_path
    assert_text /Evidence withdrawn/i
    assert_text "retained for review but excluded from AI context"
    assert_text source.body
    clear_enqueued_jobs
    assert_no_enqueued_jobs(only: IngestKnowledgeSourceJob) do
      click_button "Re-ingest", exact: true
      assert_text "Supporting evidence was withdrawn. Re-ingestion was not queued."
      assert_current_path admin_knowledge_source_path(source)
    end
    assert_not source.reload.available?
    assert_equal chunks, source.knowledge_chunks.order(:id).map(&:attributes)
    within "#admin-sidebar" do
      click_link "Knowledge Sources", exact: true
    end
    within "tr", text: source.title do
      assert_text /Evidence withdrawn/i
      assert_text /Approved/i
    end
  end
end
