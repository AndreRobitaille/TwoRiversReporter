require "test_helper"

class Admin::TranscriptImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  setup do
    @admin = User.create!(email_address: "transcript-admin@example.com", password: "password123456", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!
    @mfa_pending_admin = User.create!(email_address: "transcript-pending@example.com", password: "password123456", admin: true, totp_enabled: false)
    @mfa_pending_admin.ensure_totp_secret!
    @committee = Committee.create!(name: "Plan Commission")
    @meeting = Meeting.create!(body_name: "Plan Commission Meeting", detail_page_url: "https://example.com/meetings/plan-commission", starts_at: Time.zone.local(2026, 6, 14, 18, 30), committee: @committee)
  end

  test "unauthenticated access is blocked" do
    get admin_transcript_imports_path
    assert_redirected_to new_session_path

    post admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: youtube_url } }
    assert_redirected_to new_session_path

    post check_url_admin_transcript_imports_path, params: { transcript_import: { youtube_url: youtube_url } }
    assert_redirected_to new_session_path
  end

  test "password-authenticated but mfa-pending user is blocked" do
    post session_url, params: { email_address: @mfa_pending_admin.email_address, password: "password123456" }

    get admin_transcript_imports_path
    assert_redirected_to new_session_path

    post admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: youtube_url } }
    assert_redirected_to new_session_path
  end

  test "authenticated admin can see transcript imports page" do
    sign_in_as_admin

    get admin_transcript_imports_path

    assert_response :success
    assert_select "h1", text: "Transcript Imports"
    assert_select "form[action=?][method=post]", admin_transcript_imports_path do
      assert_select "option[value='']", text: "Choose a meeting"
      assert_select "select[name='transcript_import[meeting_id]']"
      assert_select "input[name='transcript_import[youtube_url]']"
      assert_select "button[type='submit'][formaction='#{check_url_admin_transcript_imports_path}'][formmethod='post']", text: "Check URL"
      assert_select "input[type=submit][value='Begin Import']"
    end
    assert_select "aside", text: /What this job does/i
    assert_select "aside", text: /workflow logs each step/i
  end

  test "authenticated admin sees failed workflow details and step logs" do
    sign_in_as_admin

    meeting_document = @meeting.meeting_documents.create!(document_type: "transcript", source_url: youtube_url, extracted_text: "Transcript", text_quality: "auto_transcribed", text_chars: 10)
    transcript_import = TranscriptImport.create!(
      meeting: @meeting,
      youtube_url: youtube_url,
      status: "failed",
      meeting_document: meeting_document,
      error_class: "StandardError",
      error_message: "boom",
      step_logs: [
        { "at" => Time.current.iso8601, "level" => "info", "step" => "workflow", "message" => "Transcript import workflow started", "metadata" => {} },
        { "at" => Time.current.iso8601, "level" => "error", "step" => "download_transcript", "message" => "boom", "metadata" => { "error_class" => "StandardError" } }
      ]
    )

    get admin_transcript_imports_path

    assert_response :success
    assert_select "details summary", text: /View logs/i
    assert_select "p", text: /StandardError: boom/
    assert_select "ol.transcript-imports-step-logs li strong", text: "download_transcript"
    assert_select "td.transcript-imports-table__log", text: /boom/
  end

  test "create enqueues workflow and creates queued record" do
    sign_in_as_admin

    assert_enqueued_with(job: Admin::TranscriptImportWorkflowJob) do
      post admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: youtube_url } }
    end

    assert_redirected_to admin_transcript_imports_path
    assert_match(/Transcript import workflow queued/i, flash[:notice])
    assert_equal 1, TranscriptImport.count
    assert_equal "queued", TranscriptImport.last.status
  end

  test "invalid meeting does not enqueue and alerts" do
    sign_in_as_admin

    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: { transcript_import: { meeting_id: 0, youtube_url: youtube_url } }
    end

    assert_redirected_to admin_transcript_imports_path
    assert_match(/Choose a valid meeting/i, flash[:alert])
  end

  test "missing meeting does not enqueue and alerts" do
    sign_in_as_admin

    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: { transcript_import: { meeting_id: "", youtube_url: youtube_url } }
    end

    assert_redirected_to admin_transcript_imports_path
    assert_match(/Choose a valid meeting/i, flash[:alert])
  end

  test "invalid url does not enqueue and alerts" do
    sign_in_as_admin

    assert_no_enqueued_jobs do
      post admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: "https://example.com/not-youtube" } }
    end

    assert_redirected_to admin_transcript_imports_path(meeting_id: @meeting.id, youtube_url: "https://example.com/not-youtube")
    assert_match(/Enter a valid YouTube watch URL/i, flash[:alert])
  end

  test "check_url preserves meeting and is non-destructive" do
    sign_in_as_admin

    precheck = Documents::TranscriptDownloader::PrecheckResult.new(status: :captions_available, message: "Captions available", details: nil)
    Documents::TranscriptDownloader.stub(:precheck, precheck) do
      assert_no_difference("TranscriptImport.count") do
        post check_url_admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: youtube_url } }
      end
    end

    assert_redirected_to admin_transcript_imports_path(meeting_id: @meeting.id, youtube_url: youtube_url)
    assert_match(/Captions available/i, flash[:notice])
  end

  test "check_url trims url whitespace" do
    sign_in_as_admin

    precheck = Documents::TranscriptDownloader::PrecheckResult.new(status: :captions_available, message: "Captions available", details: nil)
    Documents::TranscriptDownloader.stub(:precheck, precheck) do
      post check_url_admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: "  #{youtube_url}  " } }
    end

    assert_redirected_to admin_transcript_imports_path(meeting_id: @meeting.id, youtube_url: youtube_url)
  end

  test "check_url alerts for invalid url, captions missing, and verification unavailable" do
    sign_in_as_admin

    { invalid_url: :invalid_url, captions_missing: :captions_missing, verification_unavailable: :verification_unavailable }.each do |key, status|
      precheck = Documents::TranscriptDownloader::PrecheckResult.new(status: status, message: "#{key.to_s.humanize} message", details: nil)
      Documents::TranscriptDownloader.stub(:precheck, precheck) do
        post check_url_admin_transcript_imports_path, params: { transcript_import: { meeting_id: @meeting.id, youtube_url: youtube_url } }
        assert_redirected_to admin_transcript_imports_path(meeting_id: @meeting.id, youtube_url: youtube_url)
        assert_match(/#{key.to_s.humanize} message/i, flash[:alert])
      end
    end
  end

  private

  def sign_in_as_admin
    post session_url, params: { email_address: @admin.email_address, password: "password123456" }
    post mfa_session_url, params: { code: ROTP::TOTP.new(@admin.totp_secret).now }
  end

  def youtube_url
    "https://www.youtube.com/watch?v=abc123"
  end
end
