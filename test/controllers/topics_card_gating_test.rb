require "test_helper"

class TopicsCardGatingTest < ActionDispatch::IntegrationTest
  HEADLINE = "The council is weighing a stormwater utility fee that would add a " \
             "monthly charge to every household water bill starting next spring".freeze

  setup do
    # Topic must clear the same visibility bar as the rest of the index:
    # publicly_visible (approved) + active lifecycle + at least one agenda
    # item (the index inner-joins agenda_items), plus recent last_activity_at
    # so it lands in the hero grid deterministically.
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 2.days.ago,
      detail_page_url: "https://example.com/meeting"
    )
    @agenda_item = AgendaItem.create!(meeting: @meeting, title: "Stormwater utility fee discussion")
    @topic = Topic.create!(
      name: "Stormwater Utility Fee",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      last_activity_at: 2.days.ago
    )
    AgendaItemTopic.create!(topic: @topic, agenda_item: @agenda_item)
    @topic.create_topic_briefing!(headline: HEADLINE, generation_tier: "headline_only")
  end

  test "anonymous visitor gets a truncated topic headline" do
    set_access_mode("gated")

    get topics_path

    assert_response :success
    assert_match(/teaser-fade/, response.body)
    assert_no_match(/starting next spring/, response.body)

    # Pin the fade modifier: a wrong `fade:` value (e.g. :block) would still
    # pass every assertion above, but would render "teaser-fade" alone
    # instead of "teaser-fade teaser-fade--inline".
    assert_match(/teaser-fade teaser-fade--inline/, response.body)

    # Pin the truncation boundary itself. HEADLINE's truncated form,
    # measured directly (irb: `String.new(HEADLINE).truncate(90, separator:
    # " ", omission: "")`), truncates at chars: 90 to exactly:
    #   "The council is weighing a stormwater utility fee that would add a
    #    monthly charge to every" (89 chars -- the word-boundary truncate
    #    backs off from 90 to the last space)
    # "every" is the word at offsets 84-89 (last word kept); "household" is
    # the word at offsets 90-99 (first word cut). A wrong chars: value (e.g.
    # 150, which keeps "household") would still pass every assertion above
    # but would fail these two. Pinned as the phrase "charge to every"
    # rather than the bare word "every" -- the og:description/twitter:description
    # boilerplate on this page also contains "every" ("tracked across every
    # city meeting", "through every vote"), so a bare /every/ match would
    # false-pass even when the headline itself was truncated too early
    # (verified: chars: 60 still matched a bare /every/ via the boilerplate).
    assert_match(/charge to every\b/, response.body)
    assert_no_match(/household/, response.body)
  end

  test "signed-in member gets the whole headline" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "topic-reader@example.com", status: "active"))

    get topics_path

    assert_match(/starting next spring/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
