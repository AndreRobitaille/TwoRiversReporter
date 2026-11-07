require "test_helper"
require_relative "../support/briefing_withdrawal_scenario"

class CouncilSourceWithdrawalTest < ActionDispatch::IntegrationTest
  include BriefingWithdrawalScenario
  include ActiveJob::TestHelper
  self.use_transactional_tests = false

  setup do
    @previous_setting = SiteSetting.first
    @previous_mode = @previous_setting&.access_mode
    SiteSetting.instance.update!(access_mode: "open")
    build_withdrawal_scenario
    _, secret = ApiAccessToken.issue!(user: @actor, name: "Synthetic source reader", expires_in: 1.day)
    @bearer = { "Authorization" => "Bearer #{secret}" }
  end

  teardown do
    ApiAccessToken.where(user_id: @actor&.id).delete_all
    Session.where(user_id: @actor&.id).delete_all
    PasskeyCredential.where(user_id: @actor&.id).delete_all
    KnownContext.where(user_id: @actor&.id).delete_all
    clean_withdrawal_scenario
    if @previous_setting
      @previous_setting.update!(access_mode: @previous_mode)
    else
      SiteSetting.first&.destroy!
    end
  end

  test "new downloaded bytes withdraw a motion-only briefing before new extraction and preserve unrelated analysis" do
    assert_empty @briefing.generation_data.fetch("source_catalog")
    original = @briefing.attributes.slice("headline", "generation_data", "editorial_content", "last_full_generation_at")
    other = @other_briefing.attributes
    image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", source_briefing: @briefing)
    image.file.attach(io: File.open(Rails.root.join("public/icon.png")), filename: "synthetic.png", content_type: "image/png")
    get topic_path(@topic)
    assert_includes response.body, STORY
    assert_select ".topic-feature-image img", count: 1
    etag = response.headers.fetch("ETag")
    since = Time.current
    without_paid_providers do
      travel 2.seconds do
        download("Synthetic revised minutes awaiting extraction")
        assert_not_nil @briefing.reload.evidence_withdrawn_at
        assert_nil @briefing.withdrawal_correction_id
        get topic_path(@topic), headers: { "If-None-Match" => etag }
        assert_response :success
        refute_includes response.body, STORY
        assert_select ".topic-feature-image img", count: 0
        assert_includes response.body, "supporting evidence changed"
        assert_select "a[href='#{meeting_path(@meeting)}']"
        get "/api/v1/topics/#{@topic.id}", headers: @bearer
        assert_nil response.parsed_body.dig("data", "briefing")
        get "/api/v1/topics", params: { updated_since: since.iso8601(6) }, headers: @bearer
        assert_equal [ @topic.id ], response.parsed_body.fetch("data").map { |row| row["id"] }
        # The old published motion still exists, but cannot restore stale prose.
        Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      end
    end
    assert_nil @topic.reload.published_topic_briefing
    assert_equal original, @briefing.reload.attributes.slice(*original.keys)
    assert_equal other, @other_briefing.reload.attributes
    assert_equal "superseded", image.reload.status
    audits = AuditEvent.where(subject: @briefing, action: "topic_briefing.source_withdrawn")
    assert_equal 1, audits.count
    audit = audits.sole
    assert_nil audit.actor_id
    assert_equal "document_dependencies_v1", audit.metadata.fetch("method")
    assert_equal "source_changed", audit.metadata.fetch("reason")
    assert_equal original.fetch("generation_data").fetch("evidence_manifest"), audit.metadata.fetch("evidence_manifest")
    assert_equal Citations::SourceCatalog.snapshot(@document.reload), audit.metadata.fetch("current_source")
    assert_equal 2, @document.reload.source_versions.count
    assert_nil @document.current_text_version
    assert_equal "yes", @meeting.motions.sole.votes.sole.value
    sign_in_as(@actor)
    get admin_audit_events_path
    assert_response :success
    assert_select "tbody tr", text: /Automated.*topic_briefing\.source_withdrawn.*Topic: #{Regexp.escape(@topic.name)}/m, count: 1
  end

  test "unchanged responses failed fetches and restored identical evidence do not request generation" do
    bytes = @document.file.download
    original = @briefing.attributes
    without_paid_providers do
      download(bytes)
      response_io = StringIO.new
      response_io.define_singleton_method(:status) { [ "304", "Not Modified" ] }
      URI.stub(:open, ->(*) { raise OpenURI::HTTPError.new("Not Modified", response_io) }) do
        Documents::DownloadJob.perform_now(@document.id)
      end
      URI.stub(:open, ->(*) { raise IOError, "Synthetic fetch failure" }) { Documents::DownloadJob.perform_now(@document.id) }
      assert_equal original, @briefing.reload.attributes
      assert_equal 1, @document.source_versions.count
      download("Synthetic changed artifact")
      assert_not_nil @briefing.reload.evidence_withdrawn_at
      download(bytes)
      assert_nil @topic.reload.published_topic_briefing
      assert_no_enqueued_jobs do
        Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      end
    end
    assert_not_nil @topic.reload.published_topic_briefing
    assert_equal original.slice("generation_data", "last_full_generation_at"), @briefing.reload.attributes.slice("generation_data", "last_full_generation_at")
    assert_equal 2, @document.source_versions.count
    assert_equal 1, AuditEvent.where(subject: @briefing, action: "topic_briefing.source_withdrawn").count
  end

  test "text publication withdraws dependent motion analysis only after a changed complete projection" do
    text = @document.extracted_text
    without_paid_providers do
      refute Documents::PublishText.new(@document.reload).call(raw_pages: [ text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
      assert_not_nil @topic.reload.published_topic_briefing
      Documents::PublishText.new(@document.reload).call(raw_pages: [ "Corrected synthetic OCR: motion failed." ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
      assert_nil @topic.reload.published_topic_briefing
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
    end
    assert_equal 2, @document.source_versions.sole.text_versions.count
    assert_equal "passed", @meeting.motions.sole.outcome
  end

  test "document deletion and a new document at the same URL cannot substitute for a retained catalog" do
    catalog_briefing
    retained = @other_briefing.reload.generation_data
    assert_equal [ @document.id ], retained.fetch("source_catalog").map { |source| source.fetch("document_id") }
    get topic_path(@other)
    assert_includes response.body, "Synthetic maple story"
    id, url, text = @document.id, @document.source_url, @document.extracted_text
    without_paid_providers do
      @document.destroy!
      replacement = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: url, extracted_text: text)
      assert_not_equal id, replacement.id
      assert_nil @other.reload.published_topic_briefing
      get topic_path(@other)
      refute_includes response.body, "Synthetic maple story"
      assert_select "a[href='#{meeting_path(@meeting)}']"
      refute Topics::GenerationEvidence.sources_current?(retained.fetch("source_catalog"))
    end
    audit = AuditEvent.where(subject: @other_briefing, action: "topic_briefing.source_withdrawn").sole
    assert_equal "source_unavailable", audit.metadata.fetch("reason")
    assert_nil audit.metadata.fetch("current_source")
    assert_equal retained.fetch("source_catalog"), audit.metadata.fetch("source_catalog")
    assert_equal retained, @other_briefing.reload.generation_data
    assert MeetingDocumentVersion.find_by!(original_document_id: id).file.attached?
  end

  test "rolled back and temporary source changes do not withdraw committed evidence" do
    original = @document.source_url
    without_paid_providers do
      MeetingDocument.transaction do
        @document.update!(source_url: "https://example.test/temporary.pdf")
        @document.update!(source_url: original)
      end
      assert_not_nil @topic.reload.published_topic_briefing
      MeetingDocument.transaction do
        @document.update!(source_url: "https://example.test/rolled-back.pdf")
        raise ActiveRecord::Rollback
      end
    end
    assert_equal original, @document.reload.source_url
    assert_not_nil @topic.reload.published_topic_briefing
    assert_nil @briefing.reload.evidence_withdrawn_at
  end

  test "attachment purge withdraws known catalog evidence but metadata refresh does not" do
    catalog_briefing
    without_paid_providers do
      @document.update!(etag: "fresh-cache-header", fetched_at: Time.current)
      assert_not_nil @other.reload.published_topic_briefing
      @document.file.purge
      assert_nil @other.reload.published_topic_briefing
    end
    assert @document.source_versions.sole.file.attached?, "Retained artifact remains attached to its immutable version"
  end

  test "failed withdrawal rolls back source publication and its audit together" do
    retained = @document.reload.attributes
    without_paid_providers do
      AuditEvent.stub(:record!, ->(**) { raise "Synthetic audit write failure" }) do
        download("Synthetic revision that must not commit")
      end
    end
    assert_equal retained, @document.reload.attributes
    assert_not_nil @topic.reload.published_topic_briefing
    assert_equal 1, @document.source_versions.count
    assert_empty AuditEvent.where(subject: @briefing, action: "topic_briefing.source_withdrawn")
  end

  test "source changed during rendering cannot publish late prose" do
    @provider.define_singleton_method(:render_topic_briefing) do |*, **|
      MeetingDocument.find(@source_document_id).update!(source_url: "https://example.test/revised.pdf")
      { "editorial_content" => "Synthetic late source prose", "record_content" => "Late record" }
    end
    @provider.instance_variable_set(:@source_document_id, @document.id)
    @topic.update!(name: "Synthetic cedar new generation input")
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id) }
    assert_nil @topic.reload.published_topic_briefing
    assert_equal STORY, @briefing.reload.editorial_content
  end

  test "discovery of another unavailable URL does not withdraw an unchanged pinned source" do
    without_paid_providers do
      pending = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/unavailable.pdf")
      URI.stub(:open, ->(*) { raise IOError, "Synthetic unavailable new URL" }) { Documents::DownloadJob.perform_now(pending.id) }
      assert_not_nil @topic.reload.published_topic_briefing
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
    end
    assert_nil @briefing.reload.evidence_withdrawn_at
  end

  private

  def download(bytes)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
  end

  def catalog_briefing
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", generation_data: {
      source_catalog: [ Citations::SourceCatalog.snapshot(@document.reload) ], item_details: []
    })
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @other.id, meeting_id: @meeting.id) }
  end
end
