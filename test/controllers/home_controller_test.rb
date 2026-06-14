require "test_helper"
require "base64"

class HomeControllerTest < ActionDispatch::IntegrationTest
  IMAGE_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO0yMjoAAAAASUVORK5CYII=")

  setup do
    @council_meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 5.days.ago,
      detail_page_url: "http://example.com/council"
    )

    @high_topic = Topic.create!(
      name: "lead service lines",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      last_activity_at: 3.days.ago,
      description: "Replacing aging lead water pipes"
    )

    @mid_topic = Topic.create!(
      name: "municipal borrowing",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 4,
      last_activity_at: 4.days.ago,
      description: "How the city funds big projects"
    )

    @unsafe_topic = Topic.create!(
      name: "unsafe reuse topic",
      status: "approved",
      lifecycle_status: "active",
      reuse_strategy: "unsafe_for_auto_reuse",
      resident_impact_score: 5,
      last_activity_at: 2.days.ago,
      description: "Approved but unsafe to reuse"
    )

    @low_topic = Topic.create!(
      name: "building permits",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 2,
      last_activity_at: 6.days.ago,
      description: "Permit fees and process"
    )

    # Appearances linking topics to meetings — AgendaItemTopic#after_create
    # callback creates the TopicAppearance, no explicit create needed.
    item1 = AgendaItem.create!(meeting: @council_meeting, title: "Lead Lines")
    AgendaItemTopic.create!(topic: @high_topic, agenda_item: item1)

    item2 = AgendaItem.create!(meeting: @council_meeting, title: "Borrowing")
    AgendaItemTopic.create!(topic: @mid_topic, agenda_item: item2)

    item3 = AgendaItem.create!(meeting: @council_meeting, title: "Permits")
    AgendaItemTopic.create!(topic: @low_topic, agenda_item: item3)

    item4 = AgendaItem.create!(meeting: @council_meeting, title: "Unsafe reuse")
    AgendaItemTopic.create!(topic: @unsafe_topic, agenda_item: item4)
  end

  test "renders successfully" do
    get root_url
    assert_response :success
  end

  test "top stories show highest impact topics" do
    TopicBriefing.create!(topic: @high_topic, headline: "Lead line headline", generation_tier: "full")

    get root_url
    assert_response :success
    assert_select ".top-story .story-topic", text: /lead service lines/i
    assert_select ".top-story .story-headline", text: /Lead line headline/
    assert_select ".top-story .read-more", text: /Full story/
  end

  test "top stories render ready generated images" do
    image = @high_topic.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: Time.current)
    image.file.attach(io: StringIO.new(IMAGE_BYTES), filename: "lead-lines.png", content_type: "image/png")

    get root_url
    assert_response :success

    assert_select ".top-story.top-story--with-image"
    assert_select ".top-story .story-image[alt=?]", "Illustration for lead service lines"
    # Homepage thumbnails carry no overlay label (kept clean; disclosure lives on detail pages).
    assert_select ".top-story .generated-image-label", count: 0
    assert_select ".wire-card .wire-image", count: 0
  end

  test "wire cards render ready generated images" do
    wire_topic = Topic.create!(
      name: "storm sewer grant",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 3,
      last_activity_at: 1.day.ago,
      description: "Flood control and infrastructure grant"
    )
    image = wire_topic.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: Time.current)
    image.file.attach(io: StringIO.new(IMAGE_BYTES), filename: "borrowing.png", content_type: "image/png")

    get root_url
    assert_response :success

    assert_select ".wire-card.wire-card--with-image"
    assert_select ".wire-card .wire-image[alt=?]", "Illustration for storm sewer grant"
    # Wire cards intentionally omit the per-card label (too small; one disclosure per page).
    assert_select ".wire-card .generated-image-label", count: 0
    assert_select ".top-story .story-image", count: 0
  end

  test "top stories limited to 2 items" do
    third = Topic.create!(
      name: "property taxes", status: "approved", lifecycle_status: "active",
      resident_impact_score: 5, last_activity_at: 2.days.ago
    )

    get root_url
    assert_response :success
    assert_select ".top-story, .second-story", count: 2
  end

  test "top stories require impact >= 4" do
    @high_topic.update!(resident_impact_score: 3)
    @mid_topic.update!(resident_impact_score: 3)

    get root_url
    assert_response :success
    assert_select ".top-story", count: 0
  end

  test "wire shows mid-impact topics excluding top stories" do
    get root_url
    assert_response :success

    assert_select ".wire-card .wire-topic, .wire-list-item .list-topic", minimum: 1
    wire_text = css_select(".wire-zone").text
    assert_no_match(/lead service lines/i, wire_text)
  end

  test "wire items sorted by impact desc" do
    wire_topic_a = Topic.create!(
      name: "sidewalk program", status: "approved", lifecycle_status: "active",
      resident_impact_score: 3, last_activity_at: 5.days.ago
    )
    wire_topic_b = Topic.create!(
      name: "dnr grant", status: "approved", lifecycle_status: "active",
      resident_impact_score: 2, last_activity_at: 4.days.ago
    )

    get root_url
    body = response.body
    sidewalk_pos = body.index("sidewalk program")
    dnr_pos = body.index("dnr grant")
    if sidewalk_pos && dnr_pos
      assert sidewalk_pos < dnr_pos, "Higher impact topic should appear first in wire"
    end
  end

  test "next up shows council meetings and work sessions" do
    council = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 10.days.from_now,
      detail_page_url: "http://example.com/next-council"
    )
    work_session = Meeting.create!(
      body_name: "City Council Work Session",
      starts_at: 17.days.from_now,
      detail_page_url: "http://example.com/next-ws"
    )
    Meeting.create!(
      body_name: "Plan Commission Meeting",
      starts_at: 8.days.from_now,
      detail_page_url: "http://example.com/plan"
    )

    get root_url
    assert_response :success
    assert_select ".nextup-card", count: 2
    nextup_text = css_select(".nextup-zone").text
    assert_match(/City Council/i, nextup_text)
    assert_match(/Work Session/i, nextup_text)
    assert_no_match(/Plan Commission/i, nextup_text)
  end

  test "next up renders blank body_name safely" do
    Meeting.create!(
      body_name: nil,
      starts_at: 10.days.from_now,
      detail_page_url: "http://example.com/blank-next-up"
    )
    Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 10.days.from_now,
      detail_page_url: "http://example.com/council-next-up"
    )

    get root_url
    assert_response :success

    assert_select ".nextup-card .meeting-name", text: /City Council/
  end

  test "next up limited to 2 meetings" do
    3.times do |i|
      Meeting.create!(
        body_name: (i.even? ? "City Council Meeting" : "City Council Work Session"),
        starts_at: (10 + i * 7).days.from_now,
        detail_page_url: "http://example.com/next-#{i}"
      )
    end

    get root_url
    assert_select ".nextup-card", maximum: 2
  end

  test "next up does not claim agenda missing when agenda is posted but no substantive topics are approved" do
    meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 10.days.from_now,
      detail_page_url: "http://example.com/next-agenda-posted",
      status: "agenda_posted"
    )
    meeting.meeting_documents.create!(document_type: "agenda_pdf", source_url: "http://example.com/agenda.pdf", extracted_text: "Agenda text")

    get root_url
    assert_response :success
    assert_match(/Agenda posted/, css_select(".nextup-zone").text)
    assert_no_match(/Agenda not yet posted/, css_select(".nextup-zone").text)
  end

  test "escape hatches link to topics and meetings" do
    get root_url
    assert_select "a[href='#{topics_path}']", minimum: 1
    assert_select "a[href='#{meetings_path}']", minimum: 1
  end

  test "renders with no data" do
    TopicAppearance.destroy_all
    AgendaItemTopic.destroy_all
    AgendaItem.destroy_all
    TopicStatusEvent.destroy_all
    Motion.destroy_all
    Meeting.destroy_all
    Topic.destroy_all

    get root_url
    assert_response :success
    assert_select ".story-image", count: 0
    assert_select ".wire-image", count: 0
  end

  test "populated homepage without generated images stays text first" do
    get root_url
    assert_response :success

    assert_select ".story-image", count: 0
    assert_select ".wire-image", count: 0
  end

  test "wire zone omitted when no qualifying wire topics" do
    # Remove low-impact topic so only 2 high-impact remain (both go to top stories)
    @low_topic.destroy!

    get root_url
    assert_response :success
    assert_select ".wire-zone", count: 0
  end

  test "topics outside 30-day window excluded" do
    @high_topic.update!(last_activity_at: 45.days.ago)
    @mid_topic.update!(last_activity_at: 45.days.ago)

    get root_url
    assert_select ".top-story", count: 0
  end

  test "blocked topics excluded" do
    blocked = Topic.create!(
      name: "blocked thing", status: "blocked", lifecycle_status: "active",
      resident_impact_score: 5, last_activity_at: 1.day.ago
    )

    get root_url
    assert_no_match(/blocked thing/, response.body)
  end

  test "approved unsafe topics do not appear on homepage" do
    get root_url

    assert_response :success
    assert_no_match(/unsafe reuse topic/, response.body)
  end

  test "topic description omitted from homepage cards" do
    TopicBriefing.create!(topic: @high_topic, headline: "headline", generation_tier: "full")

    get root_url
    # Descriptions are intentionally dropped from the top-six cards (too busy).
    assert_select ".story-desc", count: 0
    assert_select ".wire-desc", count: 0
  end
end
