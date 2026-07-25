require "test_helper"

# The homepage was ungated when the tiered-access work shipped; the owner
# reversed that. Anonymous visitors in `gated` mode now get roughly six words
# of every AI-generated card headline, a small inline sign-in note, and no
# page-level gate box.
class HomeGatingTest < ActionDispatch::IntegrationTest
  # The tail phrase of each headline is what the teaser must withhold; the
  # opening words are what it must keep. Both halves are asserted, because an
  # absence assertion alone would also pass if the card vanished entirely.
  TOP_HEADLINE = "Council approved the Washington Street reconstruction contract " \
                 "after residents raised concerns about driveway access".freeze
  WIRE_HEADLINE = "The commission postponed the harbor dredging permit until the " \
                  "state finishes its sediment testing".freeze
  ROW_HEADLINE = "Staff will bring the stormwater utility fee schedule back " \
                 "for a second reading in September".freeze

  NOTE_COPY = "Sign in to read more".freeze

  setup do
    # Impact 4+ and 30-day activity puts a topic in GeneratedImages::
    # HomepageTopicSelector's top-story pool; impact 2+ puts it in the wire.
    # The wire takes 4 cards then spills into rows, so five wire-eligible
    # topics are needed before anything reaches _wire_row.
    @top = create_topic("Washington Street Reconstruction", 5, 1.day.ago, TOP_HEADLINE)

    @wire = create_topic("Harbor Dredging Permit", 3, 2.days.ago, WIRE_HEADLINE)
    3.times { |i| create_topic("Wire Filler #{i}", 3, (3 + i).days.ago, "Filler headline #{i}") }

    # Sixth wire-eligible topic, oldest, so it lands past WIRE_CARD_COUNT and
    # renders as a _wire_row rather than a _wire_card.
    @row = create_topic("Stormwater Utility Fee", 2, 20.days.ago, ROW_HEADLINE)
  end

  test "anonymous visitor gets roughly six words of the top story headline" do
    set_access_mode("gated")

    get root_path

    assert_response :success
    assert_match(/Council approved the Washington/, response.body)
    assert_no_match(/driveway access/, response.body)

    # Pin the boundary itself. `String.new(TOP_HEADLINE).truncate(38,
    # separator: " ", omission: "")` is exactly "Council approved the Washington
    # Street" (38 chars) — "Street" is the last word kept, "reconstruction" the
    # first word cut. A wrong chars: value (90, say) passes both assertions
    # above and fails these two.
    assert_match(/Street/, response.body)
    assert_no_match(/reconstruction contract/, response.body)
  end

  test "anonymous visitor gets the inline fade, not the block fade" do
    set_access_mode("gated")

    get root_path

    # A wrong `fade:` value would still truncate correctly but render
    # "teaser-fade" alone, and the fade would land on empty whitespace at the
    # right edge of a full-width block instead of hugging the text.
    assert_match(/teaser-fade teaser-fade--inline/, response.body)
  end

  test "anonymous visitor gets the tease on wire cards and wire rows too" do
    set_access_mode("gated")

    get root_path

    assert_select ".wire-headline", minimum: 1
    assert_select ".wire-list-item .list-desc", minimum: 1

    assert_match(/The commission postponed the/, response.body)
    assert_no_match(/sediment testing/, response.body)

    assert_match(/Staff will bring the/, response.body)
    assert_no_match(/second reading in September/, response.body)
  end

  test "anonymous visitor gets an inline sign-in note after the faded text" do
    set_access_mode("gated")

    get root_path

    assert_select ".home-signin-note", minimum: 3
    assert_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
  end

  # The owner was explicit: no big sign-in box anywhere on this page.
  test "the homepage never renders the large gate card, gated or open" do
    set_access_mode("gated")
    get root_path
    assert_no_match(/gate-card/, response.body)

    set_access_mode("open")
    get root_path
    assert_no_match(/gate-card/, response.body)
  end

  test "signed-in member gets whole headlines and no sign-in note" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "home-reader@example.com", status: "active"))

    get root_path

    assert_response :success
    assert_match(/driveway access/, response.body)
    assert_match(/sediment testing/, response.body)
    assert_match(/second reading in September/, response.body)
    assert_no_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
    assert_no_match(/teaser-fade/, response.body)
  end

  test "open mode shows whole headlines anonymously and no sign-in note" do
    set_access_mode("open")

    get root_path

    assert_response :success
    assert_match(/driveway access/, response.body)
    assert_match(/sediment testing/, response.body)
    assert_match(/second reading in September/, response.body)
    assert_no_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
    assert_no_match(/teaser-fade/, response.body)
  end

  # The homepage's meta description is a hand-written constant in
  # index.html.erb, not derived from any headline. Pin that: the recurring
  # leak on this branch has been a helper quietly rebuilding withheld text
  # into a meta tag or share string.
  test "the homepage meta description never carries card headline text" do
    set_access_mode("gated")

    get root_path

    [ /<meta name="description" content="([^"]*)">/,
      /<meta property="og:description" content="([^"]*)">/,
      /<meta name="twitter:description" content="([^"]*)">/ ].each do |pattern|
      content = response.body[pattern, 1]
      assert_not_nil content, "homepage rendered no #{pattern.source}"
      assert_not_includes content, "driveway access"
      assert_not_includes content, "sediment testing"
    end
  end

  private

    def create_topic(name, impact, activity, headline)
      topic = Topic.create!(
        name: name,
        status: "approved",
        lifecycle_status: "active",
        resident_impact_score: impact,
        last_activity_at: activity
      )
      TopicBriefing.create!(topic: topic, headline: headline, generation_tier: "full")
      topic
    end

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
