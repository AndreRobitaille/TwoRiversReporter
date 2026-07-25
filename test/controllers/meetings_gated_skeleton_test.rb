require "test_helper"

# Below the gate, meeting show renders a skeleton of the real page: real
# section headings, real item counts, and grey placeholder bars where the
# prose would be. This pins both halves of that deal — the counts a visitor is
# allowed to see, and the words they are not.
class MeetingsGatedSkeletonTest < ActionDispatch::IntegrationTest
  # The lede is teased at MeetingsHelper::GATED_LEDE_CHARS (200). The head sits
  # inside that window and the tail past it, so one fixture proves both that
  # the visitor gets a genuine taste and that the remainder never ships.
  LEDE_HEAD = "The council spent the evening on the harbor dredging permit renewal, " \
    "working through the marina lease schedule and the shoreline setback rules that " \
    "govern the north basin before turning to the winter parking ordinance".freeze
  LEDE_TAIL = "PENUMBRA_WITHHELD_LEDE_TAIL".freeze

  DECISION_ONE = "MERIDIAN_WITHHELD_DECISION_ONE".freeze
  DECISION_TWO = "MERIDIAN_WITHHELD_DECISION_TWO".freeze
  DECISION_THREE = "MERIDIAN_WITHHELD_DECISION_THREE".freeze
  SPEAKER_NAME = "MERIDIAN_WITHHELD_SPEAKER".freeze
  SPEAKER_SUMMARY = "MERIDIAN_WITHHELD_COMMENT".freeze
  ITEM_TITLE = "MERIDIAN_WITHHELD_ITEM_TITLE".freeze
  ITEM_SUMMARY = "MERIDIAN_WITHHELD_ITEM_SUMMARY".freeze

  WITHHELD_STRINGS = [
    LEDE_TAIL, DECISION_ONE, DECISION_TWO, DECISION_THREE,
    SPEAKER_NAME, SPEAKER_SUMMARY, ITEM_TITLE, ITEM_SUMMARY
  ].freeze

  DECISION_COUNT = 3
  SPEAKER_COUNT = 2
  ITEM_COUNT = 4

  setup do
    @meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 3.days.ago,
      detail_page_url: "https://example.com/skeleton-meeting"
    )
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "#{LEDE_HEAD} #{LEDE_TAIL}",
        "highlights" => [
          { "text" => "Council voted on #{DECISION_ONE}.", "vote" => "5-0" },
          { "text" => "Council tabled #{DECISION_TWO}." },
          { "text" => "Council referred #{DECISION_THREE} to staff." }
        ],
        "public_input" => Array.new(SPEAKER_COUNT) { |i|
          { "speaker" => "#{SPEAKER_NAME}_#{i}", "summary" => "Spoke about #{SPEAKER_SUMMARY}_#{i}." }
        },
        "item_details" => Array.new(ITEM_COUNT) { |i|
          { "agenda_item_title" => "#{ITEM_TITLE}_#{i}",
            "summary" => "Deliberation over #{ITEM_SUMMARY}_#{i}." }
        }
      }
    )
  end

  test "fixture invariant: the lede head fits inside the teaser window and the tail does not" do
    teased = String.new("#{LEDE_HEAD} #{LEDE_TAIL}").truncate(
      MeetingsHelper::GATED_LEDE_CHARS, separator: " ", omission: ""
    )

    assert_includes teased, "north basin",
      "the fixture must leave a genuine taste of the lede inside the window"
    assert_not_includes teased, LEDE_TAIL,
      "the fixture tail must sit past the window or this file proves nothing"
  end

  test "anonymous gated visitor gets the gate card, then a skeleton" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_response :success
    assert_select ".gate-card", 1
    assert_select ".gated-skeleton__card", DECISION_COUNT + SPEAKER_COUNT + ITEM_COUNT
  end

  test "skeleton item counts match what a member would actually see" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_select ".gated-skeleton__card--decision", DECISION_COUNT
    # Public Input and Agenda Items sections, in document order.
    assert_select "section:nth-of-type(2) .gated-skeleton__card", SPEAKER_COUNT
    assert_select "section:nth-of-type(3) .gated-skeleton__card", ITEM_COUNT
    assert_select ".section-label", text: "Public Input · #{SPEAKER_COUNT} speakers"
  end

  test "skeleton sections keep their real headings" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    %w[Key\ Decisions Agenda\ Items].each do |label|
      assert_select ".section-label", text: label
    end
  end

  test "no withheld word appears anywhere in the anonymous response" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    WITHHELD_STRINGS.each do |withheld|
      assert_no_match(/#{Regexp.escape(withheld)}/, response.body,
        "#{withheld} reached an anonymous visitor")
    end
  end

  test "the lede is teased, not withheld entirely" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_match(/harbor dredging permit renewal/, response.body)
    assert_select "p .teaser-fade"
  end

  test "the withheld lede tail does not escape through meta or share channels" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    description = response.body[/<meta name="description" content="([^"]*)">/, 1]
    assert_not_nil description
    assert_not_includes description, LEDE_TAIL

    share = response.body[/data-share-copy-text-value="([^"]*)"/, 1]
    assert_not_nil share, "the share control must still render"
    assert_not_includes share, LEDE_TAIL
    assert_not_includes share, DECISION_ONE,
      "Key Decisions are below the gate now, so share text may not carry them"
  end

  test "the skeleton is aria-hidden and paired with a real screen-reader line" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_select ".gated-skeleton[aria-hidden=?]", "true", 3
    assert_select "p.sr-only", text: /#{DECISION_COUNT} key decisions withheld/
    assert_select "p.sr-only", text: /#{SPEAKER_COUNT} public comments withheld/
    assert_select "p.sr-only", text: /#{ITEM_COUNT} agenda items withheld/
  end

  test "signed-in member sees the real prose and no skeleton at all" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "skeleton-reader@example.com", status: "active"))

    get meeting_path(@meeting)

    WITHHELD_STRINGS.each do |withheld|
      assert_match(/#{Regexp.escape(withheld)}/, response.body,
        "#{withheld} should be visible to a member")
    end
    assert_select ".gated-skeleton", false, "members must never see placeholder bars"
    assert_select ".gate-card", false
    assert_select ".teaser-fade", false, "members get the whole lede"
  end

  test "open mode shows anonymous visitors the real prose and no skeleton" do
    set_access_mode("open")

    get meeting_path(@meeting)

    assert_match(/#{Regexp.escape(DECISION_ONE)}/, response.body)
    assert_match(/#{Regexp.escape(LEDE_TAIL)}/, response.body)
    assert_select ".gated-skeleton", false
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
