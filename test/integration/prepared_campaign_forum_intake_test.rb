require "test_helper"
require_relative "../support/prepared_forum_fixture"
require_relative "../support/campaign_source_fixture"

class PreparedCampaignForumIntakeTest < ActionDispatch::IntegrationTest
  include PreparedForumFixture
  include CampaignSourceFixture

  setup do
    @admin = User.create!(email_address: "forum-editor@example.test", admin: true, status: "active")
    sign_in_as_admin(@admin)
  end

  test "one verified file preserves all speakers words timing and original bytes without creating civic people" do
    input = forum_parameters
    raw = File.read(input.fetch(:file).path)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Forum intake must stay offline" }) do
      assert_no_difference [ "Member.count", "MemberPosition.count", "Meeting.count", "CampaignRequest.count" ] do
        assert_enqueued_jobs 1, only: ExtractCampaignSourceJob do
          post admin_campaign_forum_path, params: { forum: input }
        end
      end
      source = CampaignSource.sole
      assert_redirected_to admin_campaign_source_path(source)
      original = source.current_version
      metadata = original.prepared_transcript
      assert_equal raw, metadata.fetch("original_json")
      assert_equal Digest::SHA256.hexdigest(raw), metadata.fetch("sha256")
      assert_equal @admin.id, metadata.fetch("reviewed_by_id")
      assert metadata.fetch("speaker_attribution_verified")
      refute metadata.fetch("transcription_verified")
      assert_equal forum_export.fetch("wordCount"), metadata.fetch("word_count")
      assert_equal forum_export.fetch("names").sort, metadata.fetch("segments").map { |row| row.fetch("speaker") }.uniq.sort
      assert_equal "reviewer_identified_moderator_filler", metadata.fetch("segments")[2].fetch("attribution")
      metadata.fetch("segments").each do |segment|
        assert_equal segment.fetch("text"), original.body[segment.fetch("text_start")...segment.fetch("text_end")]
        assert_operator segment.fetch("end_ms"), :>=, segment.fetch("start_ms")
      end
      get admin_campaign_source_path(source)
      assert_select "[data-prepared-forum]", text: /Avery Example/
      assert_select "[data-campaign-source-text]", text: /Keep the library open on Saturdays/
      assert_select "[data-forum-original]", text: raw
      assert_select "a", text: "Replace transcript"
      assert_no_difference [ "CampaignSource.count", "CampaignSourceVersion.count", "CampaignRequest.count" ] do
        post admin_campaign_forum_path, params: { forum: forum_parameters }
        get admin_campaign_source_path(source)
      end
      assert_equal original.id, source.reload.current_version.id
    end
  end

  test "replacement retains original attribution and generic article edits cannot detach its source file" do
    post admin_campaign_forum_path, params: { forum: forum_parameters }
    source = CampaignSource.sole
    original = source.current_version
    changed = forum_export
    changed["annotations"][1]["speaker"] = changed.fetch("names").index("Taylor Example")
    input = forum_parameters(changed).merge(source_id: source.id, gaps_are_moderator: "0")
    post admin_campaign_forum_path, params: { forum: input }
    assert_redirected_to admin_campaign_source_path(source)
    corrected = source.reload.current_version
    assert_not_equal original.id, corrected.id
    assert_equal "Taylor Example", corrected.prepared_transcript.fetch("segments")[1].fetch("speaker")
    assert_nil corrected.prepared_transcript.fetch("segments")[2].fetch("speaker")
    get admin_campaign_source_path(source, version: original.id)
    assert_select "[data-campaign-source-text]", text: /Jordan Example\s+Repair water lines/
    get admin_campaign_source_path(source)
    assert_select "[data-campaign-source-text]", text: /Taylor Example\s+Repair water lines/
    assert_select "[data-campaign-source-text]", text: /Unattributed speaker\s+Thanks/
    assert_no_difference "CampaignSourceVersion.count" do
      patch admin_campaign_source_path(source), params: { campaign_source: { body: "Unlinked replacement", prepared_transcript: "" } }
      assert_redirected_to new_admin_campaign_forum_path(source_id: source.id)
      post admin_campaign_forum_path, params: { forum: forum_parameters }
    end
    assert_equal corrected.id, source.reload.current_version.id
  end

  test "invalid labels and missing verification leave a correctable form without a saved source" do
    invalid = forum_export
    invalid["annotations"].last["end"] += 1
    assert_no_difference [ "CampaignSource.count", "CampaignSourceVersion.count" ] do
      post admin_campaign_forum_path, params: { forum: forum_parameters(invalid) }
      assert_response :unprocessable_entity
      assert_includes response.body, "non-overlapping word ranges"
      assert_select "input[name='forum[publisher]'][value='Example Civic Association']"
      post admin_campaign_forum_path, params: { forum: forum_parameters.merge(speaker_verified: "0") }
      assert_response :unprocessable_entity
      assert_includes response.body, "Confirm that the speaker labels"
    end
  end

  test "private verified reads precede denial of ordinary and logged-out uploads and history" do
    post admin_campaign_forum_path, params: { forum: forum_parameters }
    source = CampaignSource.sole
    get admin_campaign_source_path(source)
    assert_response :success
    assert_includes response.body, "Keep the library open on Saturdays"
    reader = User.create!(email_address: "forum-reader@example.test", status: "active")
    reader.passkey_credentials.create!(external_id: "forum-reader-key", public_key: "public-key", sign_count: 0)
    sign_in_as(reader)
    get admin_campaign_source_path(source)
    assert_redirected_to root_path
    assert_not_includes response.body, "Keep the library open on Saturdays"
    assert_no_difference "CampaignSourceVersion.count" do
      post admin_campaign_forum_path, params: { forum: forum_parameters.merge(source_id: source.id) }
      assert_redirected_to root_path
    end
    delete public_session_path
    [ new_admin_campaign_forum_path, admin_campaign_source_path(source),
      admin_campaign_source_path(source, version: source.current_version.id, format: :json) ].each do |path|
      get path
      assert_response :redirect
      assert_not_includes response.body, "Keep the library open on Saturdays"
    end
  end

  test "existing article version identities survive the added transcript metadata" do
    source = CampaignSource.create!(campaign_article_attributes)
    legacy_fields = CampaignSource::SNAPSHOT_FIELDS - [ "prepared_transcript" ]
    legacy_key = Digest::SHA256.hexdigest(JSON.generate([ source.id, source.attributes.slice(*legacy_fields) ]))
    assert_equal legacy_key, source.current_version.version_key
    assert_empty source.current_version.prepared_transcript
  end
end
