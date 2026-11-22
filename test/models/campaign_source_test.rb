require "test_helper"
require_relative "../support/campaign_source_fixture"

class CampaignSourceTest < ActiveSupport::TestCase
  include CampaignSourceFixture

  test "source corrections retain earlier text and unchanged saves reuse its version" do
    source = CampaignSource.create!(campaign_article_attributes)
    original = source.current_version
    saved_at = source.updated_at
    travel 1.day do
      source.update!(campaign_article_attributes)
    end
    assert_equal saved_at, source.reload.updated_at
    assert_equal original.id, source.current_version.id
    assert_equal 1, source.versions.count

    source.update!(coverage: "selected_excerpts", coverage_notes: "Only question one", body: "Corrected excerpt")
    assert_equal 2, source.versions.count
    assert_equal campaign_article_attributes[:body], original.reload.body
    assert_equal "full_article", original.coverage
    assert_equal "Corrected excerpt", source.current_version.body
    assert_equal Digest::SHA256.hexdigest("Corrected excerpt"), source.current_version.content_sha256
    assert_raises(ActiveRecord::ReadonlyAttributeError) { original.update!(body: "Replacement") }

    source.update!(campaign_article_attributes.merge(coverage_notes: nil))
    assert_equal 2, source.versions.count
    assert_equal original.id, source.current_version.id
  end

  test "incomplete input and unsafe publisher links never create a source version" do
    [ { body: "" }, { election_on: nil }, { coverage: "forum" },
      { source_url: "javascript:alert(1)" }, { source_url: "https://secret@example.test/article" } ].each do |invalid|
      assert_no_difference "CampaignSourceVersion.count" do
        assert_not CampaignSource.new(campaign_article_attributes.merge(invalid)).save
      end
    end
    source = CampaignSource.create!(campaign_article_attributes.merge(published_on: nil))
    assert_nil source.current_version.published_on
  end
end
