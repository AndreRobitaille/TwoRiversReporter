require "test_helper"
require "minitest/mock"
require "vips"

class CandidatePortraitsTest < ActionDispatch::IntegrationTest
  NAME = "Mark Bittner"
  IMAGE = "https://media-cdn.socastsrm.com/wordpress/wp-content/blogs.dir/1960/files/2027/03/mark.jpg"

  setup do
    travel_to Date.new(2027, 2, 1)
    @member = Member.create!(name: NAME)
    @council = Committee.create!(name: "City Council")
    CommitteeMembership.create!(committee: @council, member: @member, role: "member", source: "admin_manual")
  end

  test "saving an uncataloged questionnaire publishes its labeled photo and repeated intake reuses the thumbnail" do
    sign_in_as_admin(User.create!(email_address: "portrait-editor@example.test", admin: true, status: "active"))
    path = "https://www.seehafernews.com/2027/03/19/council-answers/"
    html = <<~HTML
      <article><div class="entry-content"><h2>Mark Bittner</h2>
      <figure><img title="Mark Bittner headshot" src="#{IMAGE}"></figure>
      <h2>Another Person</h2><figure><img title="Another Person headshot" src="#{IMAGE}"></figure>
      </div></article>
    HTML
    Tempfile.create([ "article", ".html" ]) do |file|
      file.write(html)
      file.flush
      upload = -> { Rack::Test::UploadedFile.new(file.path, "text/html") }
      attrs = { source_url: path, publisher: "Seehafer News", election_on: "2027-04-06", published_on: "2027-03-19",
        coverage: "selected_excerpts", title: "Council answers", body: "#{NAME}\nMy first priority is housing." }
      Campaigns::PortraitImage.stub(:download, Vips::Image.black(90, 240).pngsave_buffer) do
        perform_enqueued_jobs(only: RefreshCandidatePortraitJob) do
          post admin_campaign_sources_path, params: { campaign_source: attrs, portrait_article: upload.call }
        end
      end
      source = CampaignSource.find_by!(source_url: path)
      assert_equal({ NAME => IMAGE }, source.questionnaire_portraits)
      assert_redirected_to admin_campaign_source_path(source)
      assert_equal source.source_url, CandidatePortrait.sole.source_url
      Campaigns::PortraitImage.stub(:download, ->(*) { flunk "downloaded the same image twice" }) do
        perform_enqueued_jobs(only: RefreshCandidatePortraitJob) do
          patch admin_campaign_source_path(source), params: { campaign_source: attrs, portrait_article: upload.call }
          RefreshCandidatePortraitJob.perform_later(NAME)
        end
      end
      assert_equal 1, CandidatePortrait.count
      assert_equal 1, source.versions.count
    end
  end

  test "a newer article updates the image and attribution on both public pages even after an older import" do
    first = article("last-election", IMAGE, date: Date.new(2024, 3, 27))
    refresh_with_image(100, 200)
    photo = CandidatePortrait.sole
    old_src = assert_public_photo(first, width: 100)
    replacement = article("new-htr", IMAGE.sub("mark.jpg", "next.jpg"), date: Date.new(2027, 3, 19))
    Campaigns::PortraitImage.stub(:download, "unreadable") do
      assert_raises(Campaigns::PortraitImage::Error) { RefreshCandidatePortraitJob.new.perform(NAME) }
    end
    assert_equal old_src, assert_public_photo(first, width: 100)
    refresh_with_image(200, 100)
    assert_not_equal old_src, assert_public_photo(replacement, width: 200)
    article("late-backfill", IMAGE, date: Date.new(2025, 3, 21))
    MemberAlias.create!(member: @member, name: "Mark J. Bittner")
    latest = article("new-seehafer", replacement.questionnaire_portraits.fetch(NAME), date: Date.new(2027, 4, 1), name: "Mark J. Bittner")
    Campaigns::PortraitImage.stub(:download, ->(*) { flunk "downloaded the same image twice" }) do
      RefreshCandidatePortraitJob.perform_now("Mark J. Bittner")
      RefreshCandidatePortraitJob.perform_now(NAME)
    end
    assert_equal photo.id, CandidatePortrait.sole.id
    assert_public_photo(latest, width: 200)
    assert_equal({ NAME => IMAGE }, first.reload.questionnaire_portraits)
    get candidate_portrait_path(photo)
    assert_response :success
    assert_equal 200, Vips::Image.jpegload_buffer(response.body).width
  end

  test "an HTR challenger has a credited guide photo before becoming a member" do
    name = "Andrew Quackenbush"
    CouncilElectionCandidateList.create!(election_on: Date.new(2027, 4, 6), names: [ name ])
    url = "https://www.htrnews.com/story/council-questionnaire/"
    html = <<~HTML
      <head><link rel="canonical" href="#{url}"></head>
      <article><div class="gnt_ar_b"><h2>#{name}</h2><figure>
      <span data-c-caption="#{name}"></span><img alt="#{name}" data-gl-src="/gcdn/presto/2027/03/01/PHTR/andrew.jpg">
      </figure></div></article>
    HTML
    source = CampaignSource.new(source_url: url, publisher: "Herald Times Reporter", title: "Candidate interviews",
      election_on: Date.new(2027, 4, 6), coverage: "selected_excerpts", body: "#{name}\nAnswer")
    assert_raises(ArgumentError) { Campaigns::ArticlePortraits.read(source, html.sub(url, "#{url}other/")) }
    source.add_article_portraits(Campaigns::ArticlePortraits.read(source, html))
    assert_no_difference -> { Member.count } do
      source.save!
      refresh_with_image(90, 240, name:)
      guide = ResidentContent::CouncilElection.new("election_on" => "2027-04-06", "signatures_open_on" => "2026-12-01",
        "filing_deadline" => "2027-01-05", "terms_ending" => {}, "candidates" => { name => url })
      ResidentContent::CouncilElection.stub(:current, guide) { get committee_path(@council.slug) }
      assert_select "#seat-andrew-quackenbush" do
        assert_select "img[src^=?]", candidate_portrait_path(CandidatePortrait.sole)
        assert_select "a[href=?]", source.source_url, text: source.publisher
        assert_select "a[href^='/members/']", count: 0
      end
    end
    member = Member.create!(name: name)
    get member_path(member)
    assert_select ".member-article-header img[src^=?]", candidate_portrait_path(CandidatePortrait.sole)
    Campaigns::PortraitImage.stub(:download, Vips::Image.black(108, 240).pngsave_buffer) do
      perform_enqueued_jobs(only: RefreshCandidatePortraitJob) { source.update!(source_url: "#{url}corrected/") }
    end
    assert_equal Campaigns::ElectionBackfill.for(2024).dig("sources", "htr", "url"), CandidatePortrait.sole.source_url
  end

  test "the historical photos can populate a fresh site without private article records" do
    assert_empty CampaignSource.all
    photos = Campaigns::LatestPortrait.catalog
    assert_equal 13, photos.size
    assert photos.values.all? { |photo| Campaigns::PortraitImage.allowed_url?(photo.image_url) }
    refresh_with_image(175, 240, name: "Katherine Dahlke")
    photo = CandidatePortrait.sole
    assert_equal "Seehafer News", photo.publisher
    assert_equal Campaigns::ElectionBackfill.for(2026).dig("sources", "seehafer", "url"), photo.source_url
  end

  private

  def article(slug, image, date:, name: NAME)
    CampaignSource.create!(source_url: "https://www.seehafernews.com/#{slug}/", publisher: "Publisher #{slug}",
      title: "Candidate answers", election_on: Date.new(date.year, 4, 6), published_on: date,
      coverage: "full_article", body: "#{name}\nAnswer", questionnaire_portraits: { name => image })
  end

  def refresh_with_image(width, height, name: NAME)
    Campaigns::PortraitImage.stub(:download, Vips::Image.black(width, height).pngsave_buffer) { RefreshCandidatePortraitJob.perform_now(name) }
  end

  def assert_public_photo(source, width:)
    get committee_path(@council.slug)
    src = assert_select("#spring-election img").first["src"]
    assert_select "#current-members img", count: 0
    get member_path(@member)
    assert_select ".member-article-header img[src=?]", src
    assert_select ".portrait-credit a[href=?]", source.source_url, text: source.publisher
    get src
    assert_response :success
    assert_equal "image/jpeg", response.media_type
    assert_equal width, Vips::Image.jpegload_buffer(response.body).width
    src
  end
end
