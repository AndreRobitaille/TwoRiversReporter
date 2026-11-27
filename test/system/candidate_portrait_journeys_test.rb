require "application_system_test_case"
require "minitest/mock"
require "vips"

class CandidatePortraitJourneysTest < ApplicationSystemTestCase
  include ActiveJob::TestHelper

  test "a resident follows the latest questionnaire photo from the phone guide to the credited profile" do
    travel_to Date.new(2027, 2, 1)
    member = Member.create!(name: "Shannon Derby")
    council = Committee.create!(name: "City Council")
    CommitteeMembership.create!(committee: council, member: member, role: "member", source: "admin_manual")
    photo = "https://www.gannett-cdn.com/presto/2027/03/01/PHTR/test.jpg"
    source = nil
    Campaigns::PortraitImage.stub(:download, Vips::Image.black(300, 900).pngsave_buffer) do
      perform_enqueued_jobs(only: RefreshCandidatePortraitJob) do
        source = CampaignSource.create!(title: "A spring questionnaire", source_url: "https://www.htrnews.com/spring-questionnaire/",
          publisher: "Herald Times Reporter", published_on: Date.new(2027, 3, 1), election_on: Date.new(2027, 4, 6),
          body: "Shannon Derby\nAnswer", coverage: "full_article", questionnaire_portraits: { member.name => photo })
      end
    end
    page.driver.browser.manage.window.resize_to(390, 844)
    visit committee_path(council.slug, anchor: "spring-election")
    within("#seat-shannon-derby") do
      assert_selector "a img"
      assert_selector("img") { |img| img.native.property("naturalWidth") == 80 && img.native.property("naturalHeight") == 240 }
      assert_equal "contain", find("img").style("object-fit").fetch("object-fit")
      assert_operator find("img").native.size.height, :>=, 76
      assert_equal "solid", find("img").style("border-top-style").fetch("border-top-style")
      click_link "Shannon Derby"
    end
    assert_current_path member_path(member)
    assert_selector ".member-identity h1", text: /Shannon Derby/i
    assert_selector ".member-article-header img"
    assert_equal "contain", find(".member-article-header img").style("object-fit").fetch("object-fit")
    assert_operator find(".member-article-header img").native.size.height, :>=, 140
    assert_link source.publisher, href: source.source_url
    assert page.evaluate_script("document.documentElement.scrollWidth <= window.innerWidth")
    page.driver.browser.manage.window.resize_to(1280, 900)
    breadcrumb = find(".member-committee-nav").native.rect
    title = find("h1").native.rect
    assert_operator title.y - breadcrumb.y - breadcrumb.height, :<=, 12, "the name should sit directly below committee navigation"
    photo = find(".member-article-header img").native.rect
    assert_operator photo.y, :<=, breadcrumb.y + 1, "the photo should share the top of the desktop header"
    visit committee_path(council.slug, anchor: "spring-election")
    assert_selector "#spring-election img"
    assert_operator find("#spring-election img").native.size.height, :>=, 92
    within("#current-members") { assert_no_selector "img", visible: :all }
  end
end
