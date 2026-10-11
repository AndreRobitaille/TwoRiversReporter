require "application_system_test_case"
require_relative "../support/offline_transcript_pipeline"
require "tmpdir"

class TranscriptPipelineJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper
  include OfflineTranscriptPipeline

  test "admin uploads a transcript and the queued real pipeline reaches both resident topics and sources" do
    build_pipeline_fixture
    admin = User.create!(email_address: "browser-transcript-admin@example.com", status: "active", admin: true)
    admin.passkey_credentials.create!(external_id: "transcript-eligibility", public_key: "fixture", sign_count: 0)
    sign_in_by_email(admin)
    click_link "Admin", exact: true
    within "#admin-sidebar" do
      click_link "Add Transcript", exact: true
    end
    assert_current_path admin_transcript_imports_path
    find("#transcript_import_meeting_id option[value='#{@meeting.id}']").select_option
    fill_in "YouTube watch URL", with: "https://www.youtube.com/watch?v=AbCdEfGhIj0"
    Dir.mktmpdir("offline-transcript-browser") do |directory|
      file = File.join(directory, "offline.srt")
      File.write(file, @srt)
      attach_file "SRT transcript file (optional)", file
      click_button "Begin Import"
    end
    assert_text "Transcript import workflow queued."
    @import = TranscriptImport.where(meeting: @meeting).sole
    assert_equal "queued", @import.status
    assert_equal @srt.b, @import.srt_file.download.b
    assert_equal [ @import.id ], enqueued_jobs.select { |job| job[:job] == Admin::TranscriptImportWorkflowJob }.sole.fetch(:args)
    with_pipeline_provider { perform_enqueued_jobs(only: Admin::TranscriptImportWorkflowJob) }
    assert_complete_state

    visit admin_transcript_imports_path
    assert_selector ".status-pill--completed", text: /completed/i
    find("summary", text: "View logs").click
    assert_text "Transcript import workflow completed"
    visit meeting_path(@meeting)
    @facts.each { |fact| assert_text fact }
    assert_selector "a[href='#{@minutes.source_url}']"
    assert_selector "a[href='#{@import.youtube_url}']"
    @topics.each_with_index do |topic, index|
      visit topic_path(topic)
      assert_selector "h1", text: /#{Regexp.escape(topic.name)}/i
      within ".topic-article-section--record" do
        assert_text @facts[index]
        assert_selector "a[href='#{meeting_path(@meeting)}']", count: 1
        find("a[href='#{meeting_path(@meeting)}']").click
      end
      assert_current_path meeting_path(@meeting)
      assert_text @facts[index]
    end
  end
end
