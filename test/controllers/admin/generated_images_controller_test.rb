require "test_helper"
require "securerandom"
require "base64"
require "tempfile"

module Admin
  class GeneratedImagesControllerTest < ActionDispatch::IntegrationTest
    include ActiveJob::TestHelper

    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: "admin@example.com", password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      @topic = Topic.create!(name: "Generated Image Topic #{SecureRandom.hex(4)}", status: "approved")
      @meeting = Meeting.create!(detail_page_url: "https://example.com/meetings/#{SecureRandom.hex(4)}", starts_at: Time.current)
    end

    test "regenerate enqueues topic job" do
      assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ @topic.id, { force: true } ]) do
        post regenerate_generated_images_url, params: {
          imageable_type: "Topic",
          imageable_id: @topic.id,
          return_to: admin_topic_path(@topic)
        }
      end

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Image regeneration queued.", flash[:notice]
    end

    test "regenerate enqueues topic job with custom prompt" do
      assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ @topic.id, { custom_prompt: "Make it warmer", force: true } ]) do
        post regenerate_generated_images_url, params: {
          imageable_type: "Topic",
          imageable_id: @topic.id,
          custom_prompt: "Make it warmer",
          return_to: admin_topic_path(@topic)
        }
      end

      assert_redirected_to admin_topic_path(@topic)
    end

    test "regenerate enqueues meeting job" do
      assert_enqueued_with(job: GeneratedImages::GenerateForMeetingJob, args: [ @meeting.id, { force: true } ]) do
        post regenerate_generated_images_url, params: {
          imageable_type: "Meeting",
          imageable_id: @meeting.id,
          return_to: admin_root_path
        }
      end

      assert_redirected_to admin_root_path
      assert_equal "Image regeneration queued.", flash[:notice]
    end

    test "regenerate enqueues meeting job with custom prompt" do
      assert_enqueued_with(job: GeneratedImages::GenerateForMeetingJob, args: [ @meeting.id, { custom_prompt: "Make it brighter", force: true } ]) do
        post regenerate_generated_images_url, params: {
          imageable_type: "Meeting",
          imageable_id: @meeting.id,
          custom_prompt: "Make it brighter",
          return_to: admin_root_path
        }
      end

      assert_redirected_to admin_root_path
    end

    test "disable marks image disabled" do
      image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: Time.current)
      image.file.attach(uploaded_png)

      post disable_generated_images_url, params: {
        imageable_type: "Topic",
        imageable_id: @topic.id,
        image_id: image.id,
        return_to: admin_topic_path(@topic)
      }

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Image disabled.", flash[:notice]
      assert_equal "disabled", image.reload.status
      assert_predicate image.file, :attached?
    end

    test "upload creates ready admin override image and supersedes old ready image" do
      old_image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: 2.hours.ago)
      old_image.file.attach(uploaded_png)

      post generated_images_url, params: {
        imageable_type: "Topic",
        imageable_id: @topic.id,
        return_to: admin_topic_path(@topic),
        generated_image: {
          file: uploaded_png,
          purpose: "feature_and_og",
          requested_size: "1200x630"
        }
      }

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Uploaded image saved.", flash[:notice]
      assert_equal "superseded", old_image.reload.status

      new_image = @topic.generated_images.order(id: :desc).first
      assert_equal "ready", new_image.status
      assert_predicate new_image, :admin_override
      assert_equal @admin, new_image.uploaded_by
      assert_predicate new_image.file, :attached?
      assert_equal "feature_and_og", new_image.purpose
      assert_equal "admin_upload", new_image.source_generation_tier
      assert_equal "1200x630", new_image.requested_size
    end

    test "create rejects invalid imageable type" do
      assert_no_difference -> { GeneratedImage.count } do
        post generated_images_url, params: {
          imageable_type: "NotARealThing",
          imageable_id: 123,
          return_to: admin_topic_path(@topic),
          generated_image: {
            file: uploaded_png,
            purpose: "feature_and_og",
            requested_size: "1200x630"
          }
        }
      end

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Imageable not found.", flash[:alert]
    end

    test "rejects spoofed png upload" do
      assert_no_difference -> { @topic.generated_images.count } do
        post generated_images_url, params: {
          imageable_type: "Topic",
          imageable_id: @topic.id,
          return_to: admin_topic_path(@topic),
          generated_image: {
            file: spoofed_png_upload,
            purpose: "feature_and_og",
            requested_size: "1200x630"
          }
        }
      end

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Upload must be a PNG, JPEG, or WebP under 10 MB.", flash[:alert]
    end

    test "panel shows latest image provenance and status" do
      briefing = TopicBriefing.create!(topic: @topic, headline: "Headline", editorial_content: "x", record_content: "x", generation_tier: "full")
      old_image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: 2.hours.ago)
      old_image.file.attach(uploaded_png)

      latest_image = @topic.generated_images.create!(
        status: "failed",
        purpose: "feature_and_og",
        admin_override: true,
        uploaded_by: @admin,
        source_briefing: briefing,
        source_generation_tier: "full",
        source_content_fingerprint: "fingerprint-123",
        model: "gpt-image-1",
        generated_at: 5.minutes.ago,
        custom_prompt: "Make it warmer",
        visual_brief: { "civic_issue" => "Downtown" },
        prompt: "Prompt text",
        failure_reason: "Model timed out"
      )
      latest_image.file.attach(uploaded_png)

      get admin_topic_path(@topic)

      assert_response :success
      assert_match "failed", response.body
      assert_match "Model timed out", response.body
      assert_match "admin override", response.body
      assert_match @admin.email_address, response.body
      assert_match "Source briefing ID", response.body
      assert_match briefing.id.to_s, response.body
      assert_match "fingerprint-123", response.body
      assert_match "gpt-image-1", response.body
      assert_match "Make it warmer", response.body
      assert_match "Visual brief", response.body
      assert_match "Prompt text", response.body
    end

    test "panel shows disabled latest image after disable" do
      image = @topic.generated_images.create!(
        status: "ready",
        purpose: "feature_and_og",
        admin_override: true,
        uploaded_by: @admin,
        source_generation_tier: "admin_upload",
        source_content_fingerprint: "fingerprint-disabled",
        generated_at: 5.minutes.ago,
        custom_prompt: "Disable me later"
      )
      image.file.attach(uploaded_png)

      post disable_generated_images_url, params: {
        imageable_type: "Topic",
        imageable_id: @topic.id,
        image_id: image.id,
        return_to: admin_topic_path(@topic)
      }

      assert_redirected_to admin_topic_path(@topic)

      get admin_topic_path(@topic)

      assert_response :success
      assert_match "disabled", response.body
      assert_match "fingerprint-disabled", response.body
      assert_match "Disable me later", response.body
      assert_match @admin.email_address, response.body
    end

    test "panel shows latest failed row even with nil generated_at" do
      failed = @topic.generated_images.create!(
        status: "failed",
        purpose: "feature_and_og",
        custom_prompt: "Retry later",
        failure_reason: "Network timeout",
        created_at: 1.minute.ago,
        updated_at: 1.minute.ago
      )
      failed.file.attach(uploaded_png)

      @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: 2.hours.ago, created_at: 2.hours.ago, updated_at: 2.hours.ago)

      get admin_topic_path(@topic)

      assert_response :success
      assert_match "Network timeout", response.body
      assert_match "failed", response.body
      assert_match "Retry later", response.body
    end

    test "invalid imageable type is rejected" do
      post regenerate_generated_images_url, params: {
        imageable_type: "NotARealThing",
        imageable_id: 1,
        return_to: admin_topic_path(@topic)
      }

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Imageable not found.", flash[:alert]
      assert_no_enqueued_jobs
    end

    test "malicious return_to falls back to admin root" do
      [ "//evil.com", "http://evil.com", "/\\evil.com" ].each do |return_to|
        post regenerate_generated_images_url, params: {
          imageable_type: "Topic",
          imageable_id: @topic.id,
          return_to: return_to
        }

        assert_redirected_to admin_root_path
      end
    end

    test "rejects non image upload" do
      assert_no_difference -> { @topic.generated_images.count } do
        post generated_images_url, params: {
          imageable_type: "Topic",
          imageable_id: @topic.id,
          return_to: admin_topic_path(@topic),
          generated_image: {
            file: text_upload,
            purpose: "feature_and_og",
            requested_size: "1200x630"
          }
        }
      end

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Upload must be a PNG, JPEG, or WebP under 10 MB.", flash[:alert]
    end

    test "rejects oversized upload" do
      assert_no_difference -> { @topic.generated_images.count } do
        post generated_images_url, params: {
          imageable_type: "Topic",
          imageable_id: @topic.id,
          return_to: admin_topic_path(@topic),
          generated_image: {
            file: oversized_png_upload,
            purpose: "feature_and_og",
            requested_size: "1200x630"
          }
        }
      end

      assert_redirected_to admin_topic_path(@topic)
      assert_equal "Upload must be a PNG, JPEG, or WebP under 10 MB.", flash[:alert]
    end

    private

    def uploaded_png
      @uploaded_png ||= begin
        @uploaded_png_tempfile = Tempfile.new([ "generated-image", ".png" ])
        @uploaded_png_tempfile.binmode
        @uploaded_png_tempfile.write(Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO1Y9WQAAAAASUVORK5CYII="))
        @uploaded_png_tempfile.rewind
        Rack::Test::UploadedFile.new(@uploaded_png_tempfile.path, "image/png")
      end
    end

    def text_upload
      @text_upload ||= begin
        @text_upload_tempfile = Tempfile.new([ "generated-image", ".txt" ])
        @text_upload_tempfile.write("plain text")
        @text_upload_tempfile.rewind
        Rack::Test::UploadedFile.new(@text_upload_tempfile.path, "text/plain")
      end
    end

    def spoofed_png_upload
      @spoofed_png_upload ||= begin
        @spoofed_png_tempfile = Tempfile.new([ "spoofed-generated-image", ".png" ])
        @spoofed_png_tempfile.write("not really a png")
        @spoofed_png_tempfile.rewind
        Rack::Test::UploadedFile.new(@spoofed_png_tempfile.path, "image/png")
      end
    end

    def oversized_png_upload
      @oversized_png_upload ||= begin
        @oversized_png_tempfile = Tempfile.new([ "generated-image-large", ".png" ])
        @oversized_png_tempfile.binmode
        @oversized_png_tempfile.write("a" * (Admin::GeneratedImagesController::MAX_UPLOAD_BYTES + 1))
        @oversized_png_tempfile.rewind
        Rack::Test::UploadedFile.new(@oversized_png_tempfile.path, "image/png")
      end
    end
  end
end
