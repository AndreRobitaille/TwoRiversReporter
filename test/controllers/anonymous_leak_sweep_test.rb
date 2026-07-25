require "test_helper"

# One canary, every gated surface. This is the net that catches a future edit
# that renders withheld text behind a CSS class instead of omitting it.
#
# The sweep is deliberately written as *two* passes over the same path list:
#
#   1. anonymous  — the canary must be absent from the raw response body
#   2. signed-in  — the canary must be *present*, so we know the fixture
#                   actually renders something on that path
#
# Without the second pass an absence assertion is worthless: a section that is
# empty for everybody looks identical to a section that is correctly gated.
# Paths where nobody ever sees the canary are listed in PRESENCE_EXEMPT with a
# reason, never silently dropped.
class AnonymousLeakSweepTest < ActionDispatch::IntegrationTest
  SECRET = "ZZQX_WITHHELD_CANARY_PHRASE".freeze

  # 86 characters, so `teaser(headline, chars: 90)` on a topic card truncates
  # at the trailing word boundary and never emits the canary, while committee
  # show's `truncate(headline, length: 120)` keeps the whole 114-char string.
  # Both boundaries are pinned in "fixture invariants" below.
  TEASED_HEADLINE_FILLER = "The commission spent the evening on the harbor dredging permit renewal and the related".freeze
  TEASED_HEADLINE = "#{TEASED_HEADLINE_FILLER} #{SECRET}".freeze

  # Meeting show teases the first highlight at 240 characters, so the canary
  # has to sit past that boundary or a correctly-gated page would still emit it.
  HIGHLIGHT_FILLER = "The council spent nearly two hours reviewing the parks and recreation " \
    "capital improvement plan before turning to the marina renovation budget, weighing dock " \
    "repair costs against grant funding timelines and the maintenance backlog flagged in last " \
    "year's facilities audit.".freeze

  SAFE_HEADLINE = "Council approved the Sweep Commission work plan.".freeze

  # Enough filler topics that the "All Topics" list spans three pages (hero
  # takes 6, page size is 20), which is what makes ?page=2 / ?page=3 a real
  # test of the two-card cap rather than a request for an empty page.
  FILLER_TOPIC_COUNT = 46

  setup do
    @committee = Committee.create!(name: "Sweep Commission", committee_type: "city", status: "active")

    build_meetings
    build_topics
    build_filler_topics
    build_member_record
  end

  # ---------------------------------------------------------------- fixture

  def build_meetings
    # (a) structured-summary path — generation_data populated
    @meeting = Meeting.create!(
      body_name: "Sweep Commission Meeting",
      starts_at: 4.days.ago,
      committee: @committee,
      detail_page_url: "https://example.com/meetings/sweep"
    )
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        # The lede headline is shown to gated visitors by design, so it must
        # stay clean — a canary here would be a false failure, not a leak.
        "headline" => SAFE_HEADLINE,
        "highlights" => [
          # The vote tally rides on the *first* highlight deliberately. Gated
          # visitors see only `highlights.first(1)`, so a canary on any later
          # highlight cannot reach the vote-suffix guard in
          # `share_text_past_bullets` — dropping that guard survived the whole
          # suite until this tally moved here.
          { "text" => "#{HIGHLIGHT_FILLER} #{SECRET}", "vote" => "5-0 #{SECRET}" },
          { "text" => "Second decision withheld entirely: #{SECRET}", "vote" => "4-1" }
        ],
        "public_input" => [ { "speaker" => "Resident One", "summary" => "Spoke about #{SECRET}." } ],
        "item_details" => [
          { "agenda_item_title" => "Storm drainage assessment", "summary" => "Deliberation over #{SECRET}." }
        ]
      }
    )

    # (b) legacy recap path — only `content`, generation_data blank. This
    # branch shipped ungated until review caught it (commit f04298d).
    @legacy_meeting = Meeting.create!(
      body_name: "Sweep Commission Legacy Meeting",
      starts_at: 6.days.ago,
      committee: @committee,
      detail_page_url: "https://example.com/meetings/sweep-legacy"
    )
    @legacy_meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      content: "The recap body records that #{SECRET} was carried unanimously.",
      generation_data: {}
    )

    # (c) agenda-only future meeting — no summary at all. Its agenda item
    # title is withheld from anonymous visitors on the topic show page
    # ("Coming Up" sits below the gate), so it must not surface here either.
    @upcoming_meeting = Meeting.create!(
      body_name: "Sweep Commission Special Meeting",
      starts_at: 5.days.from_now,
      committee: @committee,
      detail_page_url: "https://example.com/meetings/sweep-special"
    )
    # Short enough that `truncate(title, length: 40)` in the meta-description
    # fallback would emit the canary whole — otherwise the leak this path
    # exists to catch would be masked by an unrelated truncation.
    @upcoming_item = @upcoming_meeting.agenda_items.create!(
      title: "#{SECRET} easement", order_index: 1
    )

    # (d) upcoming meeting *with* an agenda-preview summary. Distinct from (c):
    # `share_text_body` only takes its `upcoming` branch when generation_data
    # is present, so without a future-dated meeting that has a summary, the
    # gated guards in `share_text_upcoming_bullets` are dead code as far as
    # every test is concerned — verified by mutating them and watching the
    # whole suite stay green.
    @upcoming_summarized = Meeting.create!(
      body_name: "Sweep Commission Preview Meeting",
      starts_at: 9.days.from_now,
      committee: @committee,
      detail_page_url: "https://example.com/meetings/sweep-preview"
    )
    @upcoming_summarized.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: {
        "headline" => SAFE_HEADLINE,
        "highlights" => [
          { "text" => "#{HIGHLIGHT_FILLER} #{SECRET}" },
          # Short and unteasable: `gated_share_text` truncates at 240 chars, so
          # a second highlight this short emits the canary whole the moment the
          # one-highlight cap is lifted.
          { "text" => "Second agenda item withheld entirely: #{SECRET}" }
        ],
        "item_details" => [
          { "agenda_item_title" => "Marina lease renewal #{SECRET}",
            "summary" => "Staff will present #{SECRET}." }
        ]
      }
    )

    # (e) upcoming meeting whose preview summary has item_details but *no*
    # highlights. `share_text_upcoming_bullets` reaches its item_details
    # branch only when the highlights list is empty, so fixture (d) — which
    # has both — never executes it. Without this second fixture, dropping the
    # `&& !gated_for_visitor?` from that branch survives the whole suite, and
    # that is leak #4's exact shape (agenda item titles in share text).
    @upcoming_items_only = Meeting.create!(
      body_name: "Sweep Commission Items-Only Meeting",
      starts_at: 11.days.from_now,
      committee: @committee,
      detail_page_url: "https://example.com/meetings/sweep-items-only"
    )
    @upcoming_items_only.meeting_summaries.create!(
      summary_type: "agenda_preview",
      generation_data: {
        "headline" => SAFE_HEADLINE,
        "highlights" => [],
        "item_details" => [
          { "agenda_item_title" => "Shoreline setback variance #{SECRET}",
            "summary" => "Staff will present #{SECRET}." }
        ]
      }
    )
  end

  def build_topics
    # The rich topic-show fixture: all four gated sections populated.
    # Canary stays out of `name`/`canonical_name` — those render in the page
    # header and card titles that gated pages correctly still show, and
    # `maintain_derived_fields` lowercases canonical_name besides.
    @topic = Topic.create!(
      name: "Sweep Storm Drainage",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 3,
      last_activity_at: 3.days.ago
    )
    @topic.create_topic_briefing!(
      headline: SAFE_HEADLINE,
      generation_tier: "full",
      editorial_content: "The editorial body explains #{SECRET} at length.",
      generation_data: {
        "editorial_analysis" => {
          # What to Watch is shown in full to gated visitors, so it stays clean.
          "what_to_watch" => "Whether the commission funds the design phase this cycle",
          "current_state" => "The Story section reports #{SECRET}."
        },
        "factual_record" => [
          { "date" => "2026-06-01", "meeting" => "Sweep Commission Meeting",
            "event" => "Staff filed #{SECRET} with the clerk." }
        ]
      }
    )

    # Key Decisions: a Motion linked to an agenda item linked to the topic.
    # The agenda item title doubles as the member show voting-record label
    # (`vote_context` prefers agenda_item.title over motion.description).
    @past_item = @meeting.agenda_items.create!(
      title: "Storm drainage assessment #{SECRET}", order_index: 1
    )
    AgendaItemTopic.create!(topic: @topic, agenda_item: @past_item)
    @motion = @meeting.motions.create!(
      description: "Motion to record #{SECRET} in the assessment.",
      outcome: "passed",
      agenda_item: @past_item
    )

    # Coming Up: an appearance on a future meeting. Created directly rather
    # than via AgendaItemTopic so @upcoming_meeting stays "thin" on the
    # meetings index (a compact row, no card).
    TopicAppearance.create!(
      topic: @topic,
      meeting: @upcoming_meeting,
      agenda_item: @upcoming_item,
      appeared_at: @upcoming_meeting.starts_at,
      body_name: @upcoming_meeting.body_name,
      committee: @committee,
      evidence_type: "agenda_item"
    )

    # Second topic: its briefing headline carries the canary past the 90-char
    # card teaser. `reuse_strategy: "unsafe_for_auto_reuse"` keeps it out of
    # `Topic.reusable`, and therefore off the homepage, where the spec says
    # briefing headlines render in full ("Home | Everything | none").
    @topic_headline = Topic.create!(
      name: "Sweep Harbor Dredging",
      status: "approved",
      lifecycle_status: "active",
      resident_impact_score: 5,
      last_activity_at: 1.day.ago,
      reuse_strategy: "unsafe_for_auto_reuse"
    )
    @harbor_item = @meeting.agenda_items.create!(title: "Harbor dredging schedule", order_index: 2)
    AgendaItemTopic.create!(topic: @topic_headline, agenda_item: @harbor_item)
    @topic_headline.create_topic_briefing!(
      headline: TEASED_HEADLINE,
      generation_tier: "headline_only"
    )
  end

  # Names sort in numeric order so the alphabetical search ordering
  # (`search_by_text` orders by name) and the last_activity_at ordering of the
  # "All Topics" list stay predictable. Canary headlines land on all-topics
  # page 1 / 2 / 3 respectively, which is what makes the ?page=N and
  # turbo_stream presence checks real.
  CANARY_FILLER_INDEXES = [ 10, 30, 45 ].freeze

  def build_filler_topics
    FILLER_TOPIC_COUNT.times do |i|
      topic = Topic.create!(
        name: format("Sweep Filler Topic %02d", i),
        status: "approved",
        lifecycle_status: "active",
        # 1 is the validation floor and stays under HomeController's
        # WIRE_MIN_IMPACT of 2, so fillers never reach the ungated homepage.
        resident_impact_score: 1,
        last_activity_at: (10 + i).days.ago,
        reuse_strategy: "unsafe_for_auto_reuse"
      )
      item = @meeting.agenda_items.create!(title: format("Filler item %02d", i), order_index: 10 + i)
      AgendaItemTopic.create!(topic: topic, agenda_item: item)

      next unless CANARY_FILLER_INDEXES.include?(i)
      topic.create_topic_briefing!(headline: TEASED_HEADLINE, generation_tier: "headline_only")
    end
  end

  def build_member_record
    @member = Member.create!(name: "Jordan Sweep")
    CommitteeMembership.create!(member: @member, committee: @committee, role: "member")
    @motion.votes.create!(member: @member, value: "yes")
  end

  # ------------------------------------------------------------------ paths

  # Every path is keyed so a failure names the surface, not just a URL.
  def sweep_paths
    {
      "home" => root_path,
      "topics index" => topics_path,
      "topics index ?page=2" => topics_path(page: 2),
      "topics index ?page=3" => topics_path(page: 3),
      "topics search (single hit)" => topics_path(q: "Harbor"),
      "topics search (many hits)" => topics_path(q: "Sweep"),
      "topics search ?page=2" => topics_path(q: "Sweep", page: 2),
      "topics index turbo_stream" => topics_path(format: :turbo_stream),
      # The HTML ?page=N variants always re-render the (unpaginated) hero grid,
      # so their presence check is carried by the hero cards rather than by the
      # paginated list. These turbo_stream variants render *only* the paginated
      # list, which is what makes the ?page=2 / ?page=3 cap-walking assertion
      # load-bearing — verified by deleting the page-2 canary and watching the
      # presence test fail.
      "topics index ?page=2 turbo_stream" => topics_path(page: 2, format: :turbo_stream),
      "topics index ?page=3 turbo_stream" => topics_path(page: 3, format: :turbo_stream),
      "meetings index" => meetings_path,
      "meetings index ?page=2" => meetings_path(page: 2),
      "meetings index ?page=3" => meetings_path(page: 3),
      "meetings search" => meetings_path(q: "Sweep"),
      "meetings search ?page=2" => meetings_path(q: "Sweep", page: 2),
      "meetings index turbo_stream" => meetings_path(format: :turbo_stream),
      "meetings index ?page=2 turbo_stream" => meetings_path(page: 2, format: :turbo_stream),
      "committees index" => committees_path,
      "topic show (four gated sections)" => topic_path(@topic),
      "topic show (meta description)" => topic_path(@topic_headline),
      "meeting show (generation_data)" => meeting_path(@meeting),
      "meeting show (legacy content)" => meeting_path(@legacy_meeting),
      "meeting show (agenda only)" => meeting_path(@upcoming_meeting),
      "meeting show (upcoming, agenda_preview summary)" => meeting_path(@upcoming_summarized),
      "meeting show (upcoming, item_details only)" => meeting_path(@upcoming_items_only),
      "committee show" => committee_path(@committee.slug),
      "member show" => member_path(@member)
    }
  end

  MEETINGS_INDEX_REASON = "The only thing the meetings index withholds is " \
    "the tail of a meeting headline past 90 characters, and that same headline is rendered in " \
    "full to gated visitors on meeting show (design spec: \"Meeting show | ... headline ...\"). " \
    "A canary there would be legitimately visible on another path and produce a false failure. " \
    "The truncation boundary itself is pinned by MeetingsIndexGatingTest.".freeze

  TURBO_406_REASON = "MeetingsController#index declares no turbo_stream format and there is no " \
    "index.turbo_stream.erb, so the request is refused with 406 for every visitor. Refusing the " \
    "format is a valid non-leak; the sweep still greps the error body for the canary.".freeze

  # Statuses a swept path may legitimately return. 406 covers the meetings
  # index turbo_stream variants above.
  ACCEPTABLE_STATUSES = [ 200, 406 ].freeze

  # Paths where the canary is invisible to *every* visitor. Each is a
  # deliberate product decision, not a broken fixture.
  PRESENCE_EXEMPT = {
    "home" => "The homepage is ungated by design (design spec: \"Home | Everything | none\"), " \
      "so it renders no withheld content to anyone. It stays in the absence sweep to prove " \
      "summary/briefing body text never reaches the home cards.",
    "committees index" => "The committees index is ungated by design and renders only committee " \
      "names and hardcoded card descriptions — there is no AI-generated content on it at all.",
    "meetings index" => MEETINGS_INDEX_REASON,
    "meetings index ?page=2" => MEETINGS_INDEX_REASON,
    "meetings index ?page=3" => MEETINGS_INDEX_REASON,
    "meetings search" => MEETINGS_INDEX_REASON,
    "meetings search ?page=2" => MEETINGS_INDEX_REASON,
    "meetings index turbo_stream" => TURBO_406_REASON,
    "meetings index ?page=2 turbo_stream" => TURBO_406_REASON
  }.freeze

  # ------------------------------------------------------------------ tests

  test "fixture invariants hold" do
    # If any of these drift, the sweep silently stops testing what it claims.
    assert_not_includes String.new(TEASED_HEADLINE).truncate(90, separator: " ", omission: ""), SECRET,
      "the 90-char card teaser must cut before the canary"
    assert_includes TEASED_HEADLINE.truncate(120), SECRET,
      "committee show truncates headlines at 120 chars and must still show the canary"
    assert_not_includes String.new("#{HIGHLIGHT_FILLER} #{SECRET}").truncate(240, separator: " ", omission: ""), SECRET,
      "the 240-char meeting-show teaser must cut before the canary"
    assert_not_includes @topic.canonical_name.to_s.upcase, SECRET,
      "the canary must never land in canonical_name (it is force-lowercased and publicly shown)"
  end

  test "no gated surface leaks the canary to an anonymous visitor" do
    set_access_mode("gated")

    sweep_paths.each do |label, path|
      get path

      assert_includes ACCEPTABLE_STATUSES, response.status,
        "#{label} (#{path}) should render anonymously, got #{response.status}"
      assert_no_match(/#{Regexp.escape(SECRET)}/i, response.body,
        "#{label} (#{path}) leaked withheld content to an anonymous visitor")
    end
  end

  test "every swept path actually renders the canary for a signed-in member" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "sweep-member@example.com", status: "active"))

    silent = []

    sweep_paths.each do |label, path|
      next if PRESENCE_EXEMPT.key?(label)

      get path

      assert_includes ACCEPTABLE_STATUSES, response.status,
        "#{label} (#{path}) should render for a signed-in member, got #{response.status}"
      silent << "#{label} (#{path})" unless response.body.include?(SECRET)
    end

    assert_empty silent, <<~MSG
      These paths never showed the canary to anybody, so their absence assertion
      in the anonymous sweep proves nothing. Fix the fixture (or add the path to
      PRESENCE_EXEMPT with a reason) — do not weaken this check:

      #{silent.join("\n")}
    MSG
  end

  # Asserting against the whole raw body already covers data-* attributes and
  # meta tags, but the two detail pages that build their description from a
  # helper get an explicit assertion too: that is where leak #2 lived, and a
  # bare-body assertion would not say *which* channel regressed.
  test "meta descriptions on helper-built detail pages never carry the canary" do
    set_access_mode("gated")

    [ topic_path(@topic), topic_path(@topic_headline),
      meeting_path(@meeting), meeting_path(@legacy_meeting), meeting_path(@upcoming_meeting) ].each do |path|
      get path

      description = response.body[/<meta name="description" content="([^"]*)">/, 1]
      assert_not_nil description, "#{path} rendered no meta description"
      assert_not_includes description, SECRET, "#{path} leaked the canary via <meta name=\"description\">"

      og = response.body[/<meta property="og:description" content="([^"]*)">/, 1]
      assert_not_includes og.to_s, SECRET, "#{path} leaked the canary via og:description"

      twitter = response.body[/<meta name="twitter:description" content="([^"]*)">/, 1]
      assert_not_includes twitter.to_s, SECRET, "#{path} leaked the canary via twitter:description"
    end
  end

  test "open mode still serves the withheld content to anonymous visitors" do
    # Guards against a regression that silently withholds content in open mode
    # — the mode this feature ships with by default.
    set_access_mode("open")

    get topic_path(@topic)
    assert_match(/#{Regexp.escape(SECRET)}/, response.body)

    get meeting_path(@meeting)
    assert_match(/#{Regexp.escape(SECRET)}/, response.body)
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
