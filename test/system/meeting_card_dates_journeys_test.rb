require "application_system_test_case"
require "base64"

class MeetingCardDatesJourneysTest < ApplicationSystemTestCase
  IMAGE_BYTES = Base64.decode64("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO0yMjoAAAAASUVORK5CYII=")
  UTILITIES_BODY = "Personnel and Finance Committee and Public Utilities Committee Joint Meeting"

  setup do
    travel_to Time.utc(2026, 11, 1, 18)
    @council = Meeting.create!(body_name: "City Council Meeting", starts_at: Time.utc(2026, 11, 3),
      detail_page_url: "https://example.test/browser-calendar-council")
    @topic = create_topic(@council, "Calendar water improvements", 5)
    utilities = Meeting.create!(body_name: UTILITIES_BODY, starts_at: Time.utc(2026, 11, 6),
      detail_page_url: "https://example.test/browser-calendar-utilities")
    @wire_topics = [ "Utilities budget", "Water service reliability" ].map { |name| create_topic(utilities, name, 3) }
    image = @wire_topics.first.generated_images.create!(status: "ready", purpose: "feature_and_og", generated_at: Time.current)
    image.file.attach(io: StringIO.new(IMAGE_BYTES), filename: "synthetic.png", content_type: "image/png")
  end

  test "resident follows the same local date from home through topic and meeting then searches again" do
    visit root_path
    within "a.top-story[href='#{topic_path(@topic)}']" do
      assert_selector ".story-meta", text: "NOV 2 · CITY COUNCIL"
    end
    find("a.top-story[href='#{topic_path(@topic)}']").click
    assert_current_path topic_path(@topic)
    within ".topic-upcoming-link[href='#{meeting_path(@council)}']" do
      assert_selector ".topic-upcoming-month", text: "NOV"
      assert_selector ".topic-upcoming-day", text: "2", exact_text: true
    end
    find(".topic-upcoming-link[href='#{meeting_path(@council)}']").click
    assert_current_path meeting_path(@council)
    assert_selector ".meeting-article-date", text: "NOVEMBER 2, 2026 · 6:00 PM"

    visit topics_path
    fill_in "q", with: @topic.name
    click_button "Search", exact: true
    within "a.topics-card[href='#{topic_path(@topic)}']" do
      assert_selector ".topics-card-meta", text: "NOV 2 · CITY COUNCIL"
    end
    find("a.topics-card[href='#{topic_path(@topic)}']").click
    assert_current_path topic_path(@topic)
    page.refresh
    assert_selector ".topic-upcoming-link[href='#{meeting_path(@council)}'] .topic-upcoming-day", text: "2", exact_text: true
    assert_equal "2026-11-03T00:00:00Z", @council.reload.starts_at.utc.iso8601
  end

  test "wire dates and full story labels remain readable with long committee names at desktop and mobile widths" do
    [ 1440, 390, 320 ].each do |width|
      page.driver.browser.manage.window.resize_to(width, 1000)
      visit root_path
      page.driver.browser.execute_async_script("const done = arguments[0]; document.fonts.ready.then(() => done(true));")
      assert_selector ".wire-card--with-image .wire-image"
      @wire_topics.each do |topic|
        within "a.wire-card[href='#{topic_path(topic)}']" do
          assert_selector ".wire-meta", text: "NOV 5 · #{UTILITIES_BODY.delete_suffix(' Meeting').upcase}"
          assert_selector ".wire-read", text: "Full story →", exact_text: true
        end
      end
      geometry = page.evaluate_script(<<~JS)
        [...document.querySelectorAll('.wire-card')].map(card => {
          const read = card.querySelector('.wire-read');
          const meta = card.querySelector('.wire-meta');
          const range = document.createRange();
          range.selectNodeContents(read);
          const lines = new Set([...range.getClientRects()].map(rect => Math.round(rect.top))).size;
          const r = read.getBoundingClientRect(), m = meta.getBoundingClientRect(), c = card.getBoundingClientRect();
          return { lines, contained: r.left >= c.left && r.right <= c.right && r.bottom <= c.bottom,
            separate: r.left >= m.right || r.top >= m.bottom || r.bottom <= m.top };
        });
      JS
      assert_equal 2, geometry.size
      geometry.each do |card|
        assert_equal 1, card.fetch("lines"), "Full story wrapped at #{width}px"
        assert card.fetch("contained"), "Full story escaped its card at #{width}px"
        assert card.fetch("separate"), "Full story overlapped the metadata at #{width}px"
      end
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, width
      page.execute_script("document.querySelector('.wire-zone').scrollIntoView({block: 'center'})")
      page.save_screenshot(Rails.root.join("tmp/screenshots/meeting-card-dates-#{width}.png"))
      within "a.wire-card[href='#{topic_path(@wire_topics.first)}']" do
        find(".wire-read").click
      end
      assert_current_path topic_path(@wire_topics.first)
      page.refresh
      assert_selector ".topic-upcoming-day", text: "5", exact_text: true
    end
  end

  private

    def create_topic(meeting, name, impact)
      topic = Topic.create!(name: name, status: "approved", lifecycle_status: "active",
        resident_impact_score: impact, last_activity_at: Time.current)
      item = meeting.agenda_items.create!(title: "#{name} proposal")
      AgendaItemTopic.create!(topic: topic, agenda_item: item)
      topic
    end
end
