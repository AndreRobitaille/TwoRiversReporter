require "test_helper"

class TopicsShowGatingTest < ActionDispatch::IntegrationTest
  WATCH = "Whether the council funds the design phase this budget cycle".freeze
  WITHHELD = "Staff recommended deferring the assessment until the grant is confirmed".freeze

  # Distinctive and long enough that it could never be mistaken for the
  # non-AI fallback sentence built from the topic name.
  FULL_HEADLINE = "Stormwater work is up for a funding vote after the engineering " \
    "study flagged sinkhole risk along the creek embankment".freeze

  setup do
    @topic = Topic.create!(name: "Stormwater Design Phase", status: "approved")
    @topic.create_topic_briefing!(
      headline: FULL_HEADLINE,
      generation_tier: "full",
      editorial_content: WITHHELD,
      generation_data: {
        "editorial_analysis" => { "what_to_watch" => WATCH, "current_state" => WITHHELD }
      }
    )
  end

  test "anonymous visitor sees What to Watch but nothing after it" do
    set_access_mode("gated")

    get topic_path(@topic)

    assert_response :success
    assert_match(/#{Regexp.escape(WATCH)}/, response.body)
    assert_no_match(/#{Regexp.escape(WITHHELD)}/, response.body)
    assert_match(/Sign in to keep reading/, response.body)
  end

  test "signed-in member sees the whole page" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "topic-show@example.com", status: "active"))

    get topic_path(@topic)

    assert_response :success
    assert_match(/#{Regexp.escape(WITHHELD)}/, response.body)
  end

  test "anonymous gated visitor's meta tags never contain the untruncated AI headline" do
    set_access_mode("gated")

    get topic_path(@topic)

    assert_response :success
    # Covers the meta description plus the og: and twitter: description tags,
    # not just the visible article body — this is the leak class the meta
    # tags introduce even when the headline is nowhere in the rendered page.
    assert_no_match(/#{Regexp.escape(FULL_HEADLINE)}/, response.body)
    assert_match(/<meta name="description" content="[^"]*still unresolved[^"]*">/, response.body)
    assert_match(/<meta property="og:description" content="[^"]*still unresolved[^"]*">/, response.body)
    assert_match(/<meta name="twitter:description" content="[^"]*still unresolved[^"]*">/, response.body)
  end

  test "signed-in member's meta description carries the full AI headline" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "topic-show-meta@example.com", status: "active"))

    get topic_path(@topic)

    assert_response :success
    assert_match(/<meta name="description" content="[^"]*#{Regexp.escape(FULL_HEADLINE)}[^"]*">/, response.body)
  end

  test "open mode shows the full AI headline in the meta description to anonymous visitors" do
    set_access_mode("open")

    get topic_path(@topic)

    assert_response :success
    assert_match(/<meta name="description" content="[^"]*#{Regexp.escape(FULL_HEADLINE)}[^"]*">/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
