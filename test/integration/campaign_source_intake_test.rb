require "test_helper"
require_relative "../support/campaign_source_fixture"

class CampaignSourceIntakeTest < ActionDispatch::IntegrationTest
  include CampaignSourceFixture

  setup do
    @admin = User.create!(email_address: "campaign-editor@example.com", admin: true, status: "active")
    sign_in_as_admin(@admin)
  end

  test "one article saves all supplied context privately without creating candidates or calling AI" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Saving an article must not call AI" }) do
      assert_no_enqueued_jobs do
        assert_no_difference [ "Member.count", "MemberPosition.count", "PromptRun.count" ] do
          post admin_campaign_sources_path, params: { campaign_source: campaign_article_attributes.merge(submitted_by_id: -1) }
        end
      end
      source = CampaignSource.sole
      assert_redirected_to admin_campaign_source_path(source)
      follow_redirect!
      assert_equal campaign_article_attributes[:body], css_select("[data-campaign-source-text]").sole.text
      assert_select "[data-campaign-source-text] script", count: 0
      assert_equal @admin.id, source.current_version.submitted_by_id
      assert_equal campaign_article_attributes[:body], source.current_version.body
      assert_match "Analysis has not been enabled", response.body

      original = source.current_version
      assert_no_difference [ "CampaignSource.count", "CampaignSourceVersion.count" ] do
        post admin_campaign_sources_path, params: { campaign_source: campaign_article_attributes }
      end
      assert_equal original.id, source.reload.current_version.id

      patch admin_campaign_source_path(source), params: { campaign_source: { body: "Revised questionnaire-cobalt", coverage: "selected_excerpts", coverage_notes: "One reviewed answer" } }
      assert_redirected_to admin_campaign_source_path(source)
      get admin_campaign_source_path(source)
      assert_select "[data-campaign-source-text]", text: "Revised questionnaire-cobalt"
      assert_includes response.body, "Selected excerpts"

      corrected_version = source.reload.current_version
      post admin_campaign_sources_path, params: { campaign_source: campaign_article_attributes }
      assert_redirected_to admin_campaign_source_path(source)
      assert_equal corrected_version.id, source.reload.current_version.id
      follow_redirect!
      assert_select "[data-campaign-source-text]", text: "Revised questionnaire-cobalt"

      get admin_campaign_source_path(source, version: original.id)
      assert_equal campaign_article_attributes[:body], css_select("[data-campaign-source-text]").sole.text
      assert_includes response.body, "Viewing an earlier version"
    end
  end

  test "article intake validation preserves the form and saved version" do
    post admin_campaign_sources_path, params: { campaign_source: campaign_article_attributes.merge(election_on: "") }
    assert_response :unprocessable_entity
    assert_select "textarea[name='campaign_source[body]']", text: campaign_article_attributes[:body]
    assert_equal 0, CampaignSource.count

    source = CampaignSource.create!(campaign_article_attributes)
    original = source.current_version
    patch admin_campaign_source_path(source), params: { campaign_source: { body: "" } }
    assert_response :unprocessable_entity
    assert_equal original.id, source.reload.current_version.id
  end

  test "overlapping edits retain the persisted combination for the next article read" do
    source = CampaignSource.create!(campaign_article_attributes)
    title_edit = CampaignSource.find(source.id)
    body_edit = CampaignSource.find(source.id)

    title_edit.update!(title: "Corrected questionnaire title")
    body_edit.update!(body: "Corrected questionnaire-cobalt answer")

    source.reload
    assert_not_nil source.current_version, "The persisted article must have a retained version"
    assert_equal 3, source.versions.count
    get admin_campaign_source_path(source)
    assert_response :success
    assert_select "h1", text: "Corrected questionnaire title"
    assert_select "[data-campaign-source-text]", text: "Corrected questionnaire-cobalt answer"

    get admin_campaign_source_path(source, version: title_edit.current_version.id)
    assert_response :success
    assert_select "h1", text: "Corrected questionnaire title"
    assert_equal campaign_article_attributes[:body], css_select("[data-campaign-source-text]").sole.text
  end

  test "a permitted admin read comes before ordinary-account and logged-out denial" do
    source = CampaignSource.create!(campaign_article_attributes)
    get admin_campaign_source_path(source)
    assert_response :success
    assert_includes response.body, "questionnaire-cobalt"

    sign_in_as(User.create!(email_address: "campaign-reader@example.com", status: "active"))
    get admin_campaign_source_path(source)
    assert_redirected_to root_path
    assert_not_includes response.body, "questionnaire-cobalt"
    assert_no_difference [ "CampaignSource.count", "CampaignSourceVersion.count" ] do
      patch admin_campaign_source_path(source), params: { campaign_source: { body: "Unauthorized change" } }
      assert_redirected_to root_path
    end

    delete public_session_path
    [ admin_campaign_source_path(source), admin_campaign_source_path(source, format: :json),
      admin_campaign_source_path(source, version: source.current_version.id), new_admin_campaign_source_path ].each do |path|
      get path
      assert_response :redirect
      assert_not_includes response.body, "questionnaire-cobalt"
    end
    post admin_campaign_sources_path, params: { campaign_source: campaign_article_attributes }
    assert_response :redirect
    assert_equal 1, CampaignSourceVersion.count
  end
end
