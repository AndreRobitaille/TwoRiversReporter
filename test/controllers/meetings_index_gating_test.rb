require "test_helper"

class MeetingsIndexGatingTest < ActionDispatch::IntegrationTest
  HEADLINE = "Council approved the Washington Street reconstruction contract " \
             "after residents raised concerns about driveway access during the " \
             "eighteen month build window and asked staff to return with options".freeze

  setup do
    @meeting = Meeting.create!(body_name: "City Council Meeting", starts_at: 2.days.ago, detail_page_url: "https://example.com/meeting")
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: { "headline" => HEADLINE }
    )
  end

  test "anonymous visitor gets only the first 90 characters of a card headline" do
    set_access_mode("gated")

    get meetings_path

    assert_response :success
    assert_match(/Council approved the Washington Street/, response.body)
    assert_no_match(/asked staff to return with options/, response.body)
    assert_match(/teaser-fade/, response.body)

    # Pin the fade modifier: a wrong `fade:` value (e.g. :block) would still
    # pass every assertion above, but would render "teaser-fade" alone
    # instead of "teaser-fade teaser-fade--inline".
    assert_match(/teaser-fade teaser-fade--inline/, response.body)

    # Pin the truncation boundary itself. HEADLINE's first 194 characters,
    # measured directly (irb: `String.new(HEADLINE).truncate(90, separator:
    # " ", omission: "")`), truncate at chars: 90 to exactly:
    #   "Council approved the Washington Street reconstruction contract after
    #    residents raised" (85 chars — the word-boundary truncate backs off
    #    from 90 to the last space)
    # "raised" is the word offsets 79-85 (last word kept); "concerns" is the
    # word at offsets 86-94 (first word cut). A wrong chars: value (e.g. 150,
    # which keeps "concerns") would still pass every assertion above but
    # would fail these two.
    assert_match(/raised/, response.body)
    assert_no_match(/concerns/, response.body)
  end

  test "signed-in member gets the whole headline" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "card-reader@example.com", status: "active"))

    get meetings_path

    assert_match(/asked staff to return with options/, response.body)
  end

  test "open mode shows the whole headline anonymously" do
    set_access_mode("open")

    get meetings_path

    assert_match(/asked staff to return with options/, response.body)
  end

  # The owner rejected the large page-level gate box on this surface. The
  # replacement is a small sign-in note directly under each faded headline —
  # it is the only thing on this page that tells a stranger access exists
  # and can be applied for, so it must survive per card, not once per page.
  NOTE_COPY = "Sign in to read this meeting".freeze

  test "anonymous visitor gets a per-card sign-in note on the meetings index" do
    set_access_mode("gated")

    get meetings_path

    assert_response :success
    assert_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
  end

  test "anonymous visitor gets a per-card sign-in note on meetings search results" do
    set_access_mode("gated")

    get meetings_path(q: "Council")

    assert_response :success
    assert_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
  end

  test "signed-in member sees no sign-in note on either meetings list" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "gate-reader@example.com", status: "active"))

    get meetings_path
    assert_no_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)

    get meetings_path(q: "Council")
    assert_no_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
  end

  test "open mode shows no sign-in note on either meetings list" do
    set_access_mode("open")

    get meetings_path
    assert_no_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)

    get meetings_path(q: "Council")
    assert_no_match(/#{Regexp.escape(NOTE_COPY)}/, response.body)
  end

  # The owner's specific complaint was the large gate box breaking the flow
  # between "Coming Up" and "What Happened" — pin its absence so nobody
  # reintroduces `render "shared/gate"` on this page.
  test "meetings index never renders the large gate card, gated or open" do
    set_access_mode("gated")
    get meetings_path
    assert_no_match(/gate-card/, response.body)
    get meetings_path(q: "Council")
    assert_no_match(/gate-card/, response.body)

    set_access_mode("open")
    get meetings_path
    assert_no_match(/gate-card/, response.body)
    get meetings_path(q: "Council")
    assert_no_match(/gate-card/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
