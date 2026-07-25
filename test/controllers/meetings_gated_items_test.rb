require "test_helper"

# Below the gate, meeting show renders the real page cut short: every section,
# every item, titles whole, bodies teased to a few words. This pins both
# halves of that deal — what a gated visitor is allowed to read, and what must
# never reach the response at all.
class MeetingsGatedItemsTest < ActionDispatch::IntegrationTest
  # The lede is teased at MeetingsHelper::GATED_LEDE_CHARS (100). The head sits
  # inside that window and the tail past it, so one fixture proves both that
  # the visitor gets a genuine taste and that the remainder never ships.
  LEDE_HEAD = "The council spent the evening on the harbor dredging permit renewal and the " \
    "marina lease".freeze
  LEDE_TAIL = "PENUMBRA_WITHHELD_LEDE_TAIL".freeze

  # Item bodies: the head fits inside GATED_ITEM_BODY_CHARS, the tail does not.
  # Both halves are asserted — a test that only checked the tail's absence
  # would pass just as happily if the whole section vanished.
  DECISION_HEAD = "Council weighed the harbor".freeze
  SPEAKER_HEAD = "Spoke about the winter".freeze
  ITEM_HEAD = "Staff presented the draft".freeze

  DECISION_TAIL = "MERIDIAN_WITHHELD_DECISION_TAIL".freeze
  SPEAKER_TAIL = "MERIDIAN_WITHHELD_COMMENT_TAIL".freeze
  ITEM_TAIL = "MERIDIAN_WITHHELD_ITEM_TAIL".freeze

  # Titles render whole below the gate, so these are *presence* fixtures, not
  # withheld ones.
  SPEAKER_NAME = "Marguerite Vandenberg".freeze
  ITEM_TITLE = "Shoreline setback variance".freeze

  # Fields the gated branch must not render at any length: votes, decision
  # badges, public-hearing lines, citations.
  VOTE_VALUE = "MERIDIAN_WITHHELD_VOTE".freeze
  DECISION_VALUE = "MERIDIAN_WITHHELD_DECISION".freeze
  HEARING_VALUE = "MERIDIAN_WITHHELD_HEARING".freeze
  CITATION_VALUE = "MERIDIAN_WITHHELD_CITATION".freeze

  # Everything an anonymous gated visitor must never receive, from any channel.
  WITHHELD_STRINGS = [
    LEDE_TAIL, DECISION_TAIL, SPEAKER_TAIL, ITEM_TAIL,
    VOTE_VALUE, DECISION_VALUE, HEARING_VALUE, CITATION_VALUE
  ].freeze

  DECISION_COUNT = 3
  SPEAKER_COUNT = 2
  ITEM_COUNT = 4

  setup do
    @meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 3.days.ago,
      detail_page_url: "https://example.com/teased-meeting"
    )
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "#{LEDE_HEAD} #{LEDE_TAIL}",
        "highlights" => Array.new(DECISION_COUNT) { |i|
          { "text" => "#{DECISION_HEAD} #{DECISION_TAIL}_#{i}.", "vote" => "#{VOTE_VALUE}_#{i}" }
        },
        "public_input" => Array.new(SPEAKER_COUNT) { |i|
          { "speaker" => "#{SPEAKER_NAME} #{i}", "summary" => "#{SPEAKER_HEAD} #{SPEAKER_TAIL}_#{i}." }
        },
        "item_details" => Array.new(ITEM_COUNT) { |i|
          { "agenda_item_title" => "#{ITEM_TITLE} #{i}",
            "summary" => "#{ITEM_HEAD} #{ITEM_TAIL}_#{i}.",
            "decision" => "#{DECISION_VALUE}_#{i}",
            "vote" => "#{VOTE_VALUE}_item_#{i}",
            "public_hearing" => "#{HEARING_VALUE}_#{i}",
            "citations" => [ "#{CITATION_VALUE}_#{i}" ] }
        }
      }
    )
  end

  test "fixture invariant: the lede head fits inside the teaser window and the tail does not" do
    teased = String.new("#{LEDE_HEAD} #{LEDE_TAIL}").truncate(
      MeetingsHelper::GATED_LEDE_CHARS, separator: " ", omission: ""
    )

    assert_equal LEDE_HEAD, teased,
      "the fixture must leave a genuine taste of the lede inside the window"
    assert_not_includes teased, LEDE_TAIL,
      "the fixture tail must sit past the window or this file proves nothing"
  end

  test "fixture invariant: every item body head fits the teaser window and every tail does not" do
    {
      DECISION_HEAD => DECISION_TAIL,
      SPEAKER_HEAD => SPEAKER_TAIL,
      ITEM_HEAD => ITEM_TAIL
    }.each do |head, tail|
      teased = String.new("#{head} #{tail}_0.").truncate(
        MeetingsHelper::GATED_ITEM_BODY_CHARS, separator: " ", omission: ""
      )

      assert_equal head, teased,
        "the fixture head must survive the #{MeetingsHelper::GATED_ITEM_BODY_CHARS}-char cut whole " \
        "and the tail must not, or the assertions below prove nothing"
    end
  end

  test "anonymous gated visitor gets the gate card, then every item" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_response :success
    assert_select ".gate-card", 1
    assert_select ".meeting-decision", DECISION_COUNT
    assert_select ".public-input-item", SPEAKER_COUNT
    assert_select ".meeting-item-card", ITEM_COUNT
    assert_select ".section-label", text: "Public Input · #{SPEAKER_COUNT} speakers"
  end

  test "gated sections keep their real headings" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    %w[Key\ Decisions Agenda\ Items].each do |label|
      assert_select ".section-label", text: label
    end
  end

  test "titles render in full below the gate" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    ITEM_COUNT.times do |i|
      assert_select ".meeting-item-card-title", text: "#{ITEM_TITLE} #{i}"
    end
    SPEAKER_COUNT.times do |i|
      assert_select ".public-input-speaker", text: "#{SPEAKER_NAME} #{i}"
    end
  end

  test "item bodies are teased: the opening words render, the tail never ships" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    [ DECISION_HEAD, SPEAKER_HEAD, ITEM_HEAD ].each do |head|
      assert_match(/#{Regexp.escape(head)}/, response.body,
        "#{head.inspect} is inside the teaser window and must be visible")
    end

    [ DECISION_TAIL, SPEAKER_TAIL, ITEM_TAIL ].each do |tail|
      assert_no_match(/#{Regexp.escape(tail)}/, response.body,
        "#{tail} sits past the teaser window and reached an anonymous visitor")
    end

    # Every teased body carries the inline fade, so the cut reads as a fade
    # rather than a typo.
    assert_select ".meeting-decision-text .teaser-fade--inline", DECISION_COUNT
    assert_select ".public-input-summary .teaser-fade--inline", SPEAKER_COUNT
    assert_select ".meeting-item-card-summary .teaser-fade--inline", ITEM_COUNT
  end

  test "no vote, decision, hearing or citation value reaches a gated visitor" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    [ VOTE_VALUE, DECISION_VALUE, HEARING_VALUE, CITATION_VALUE ].each do |value|
      assert_no_match(/#{Regexp.escape(value)}/, response.body,
        "#{value} is excluded from the gated page entirely, not truncated")
    end
    assert_select ".decision-badge", false, "no decision or vote badges below the gate"
    assert_select ".meeting-vote-breakdown", false, "no roll call below the gate"
    assert_select ".meeting-item-card-hearing", false
    assert_select ".meeting-item-card-citations", false
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

  test "withheld text does not escape through meta or share channels" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    description = response.body[/<meta name="description" content="([^"]*)">/, 1]
    assert_not_nil description
    assert_not_includes description, LEDE_TAIL

    # The Share control emits no payload at all for a gated visitor (see
    # MeetingDocumentChipGatingTest) — there is no data-share-*-value
    # attribute left for withheld text to ride along in.
    share = response.body[/data-share-copy-text-value="([^"]*)"/, 1]
    assert_nil share, "gated visitors get no share payload, so this attribute must be absent entirely"
  end

  # `share_text_upcoming_bullets` used to list agenda item titles when a
  # preview summary has item_details and no highlights, guarded so gated
  # visitors never got them in the share payload. The gated Share control no
  # longer emits any payload at all, which is a strictly stronger guarantee —
  # this pins that the title still renders on the page itself (unchanged)
  # while the share attribute that used to carry the guarded text is gone
  # entirely, not just scrubbed.
  test "titles render in full on an upcoming agenda-preview meeting, with no share payload at all" do
    upcoming = Meeting.create!(body_name: "City Council Meeting", starts_at: 6.days.from_now,
      detail_page_url: "https://example.com/teased-upcoming")
    upcoming.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: {
        "headline" => "The council will take up the marina lease.",
        "highlights" => [],
        "item_details" => [ { "agenda_item_title" => "#{ITEM_TITLE} upcoming",
                              "summary" => "#{ITEM_HEAD} #{ITEM_TAIL}_up." } ]
      }
    )

    set_access_mode("gated")
    get meeting_path(upcoming)

    assert_select ".meeting-item-card-title", text: "#{ITEM_TITLE} upcoming"

    assert_no_match(/data-share-/, response.body,
      "no data-share-*-value attribute may be emitted for a gated visitor")
  end

  test "a section with nothing in it keeps its empty state rather than vanishing" do
    bare = Meeting.create!(body_name: "City Council Meeting", starts_at: 2.days.ago,
      detail_page_url: "https://example.com/bare-meeting")
    bare.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "Council met briefly.",
        "highlights" => [ { "text" => "Council adjourned early." } ],
        "public_input" => []
      }
    )

    set_access_mode("gated")
    get meeting_path(bare)

    assert_select ".section-label", text: "Public Input"
    assert_select ".section-empty", text: /No public comments/
  end

  test "signed-in member sees the whole thing, with no gate and no fade" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "teased-reader@example.com", status: "active"))

    get meeting_path(@meeting)

    WITHHELD_STRINGS.each do |withheld|
      assert_match(/#{Regexp.escape(withheld)}/, response.body,
        "#{withheld} should be visible to a member")
    end
    assert_select ".decision-badge", minimum: 1, message: "members see decisions and votes"
    assert_select ".gate-card", false
    assert_select ".teaser-fade", false, "members get the whole lede and the whole body"
  end

  test "open mode shows anonymous visitors the real prose and no gate" do
    set_access_mode("open")

    get meeting_path(@meeting)

    assert_match(/#{Regexp.escape(DECISION_TAIL)}/, response.body)
    assert_match(/#{Regexp.escape(LEDE_TAIL)}/, response.body)
    assert_select ".gate-card", false
    assert_select ".teaser-fade", false
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
