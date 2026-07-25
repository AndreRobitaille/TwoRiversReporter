require "test_helper"

class TopicsIndexGatingTest < ActionDispatch::IntegrationTest
  setup do
    # Topics must clear the same visibility bar as the rest of the index:
    # publicly_visible (approved) + active lifecycle_status + at least one
    # agenda item (the non-search index scope inner-joins agenda_items).
    # lifecycle_status has no DB/model default, so it must be set explicitly
    # or the .active scope drops the row silently.
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 2.days.ago,
      detail_page_url: "https://example.com/meeting"
    )

    # 9 topics: the hero grid takes the top 6 by recency, leaving 3 for the
    # "All Topics" list -- enough that the turbo_stream ("Show more") path
    # actually has cards to append, so the signed-in turbo_stream assertion
    # below is exercising real data rather than an empty scope.
    9.times do |i|
      agenda_item = AgendaItem.create!(meeting: @meeting, title: "Gating sample item #{i}")
      topic = Topic.create!(
        name: "Gating Sample Topic #{i}",
        status: "approved",
        lifecycle_status: "active",
        resident_impact_score: 5,
        last_activity_at: i.days.ago
      )
      AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)
    end
  end

  test "anonymous visitor sees at most two topic cards" do
    set_access_mode("gated")

    get topics_path

    assert_response :success
    assert_operator response.body.scan(/class="topics-card(?:"|\s)/).size, :<=, 2
    assert_match(/Sign in to see every topic/, response.body)
  end

  test "signed-in member sees the full list" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "list-reader@example.com", status: "active"))

    get topics_path

    assert_operator response.body.scan(/class="topics-card(?:"|\s)/).size, :>, 2
    assert_no_match(/Sign in to see every topic/, response.body)
  end

  test "open mode shows the full list anonymously" do
    set_access_mode("open")

    get topics_path

    assert_operator response.body.scan(/class="topics-card(?:"|\s)/).size, :>, 2
    assert_no_match(/Sign in to see every topic/, response.body)
  end

  test "anonymous visitor cannot use ?page=N to see more than two cards" do
    set_access_mode("gated")

    get topics_path(page: 2)

    assert_response :success
    assert_operator response.body.scan(/class="topics-card(?:"|\s)/).size, :<=, 2
    assert_match(/Sign in to see every topic/, response.body)
  end

  # The non-search assertion above passes with or without the `page: (1 if
  # gated_for_visitor?)` pin in TopicsController#index, because the whole "All
  # Topics" section is replaced by the gate on the non-search branch — the pin
  # is inert there. The search branch is where it does real work: the view caps
  # `@search_results.first(2)`, so without the pin `?q=…&page=2` hands back a
  # *different* two topics (results 21-22), walking the cap forward two cards
  # at a time. That is leak #3's exact shape.
  #
  # This asserts card *identity*, not count: a count-only assertion passes
  # while the visitor walks the entire result set.
  test "anonymous visitor cannot use ?q=&page=N to walk past the first two search results" do
    # 25 topics beat the page size of 20, so page 2 is a genuinely different
    # slice. `search_by_text` orders by name, so the numeric suffixes fix which
    # topics land on which page.
    25.times { |i| Topic.create!(name: format("Capwalk Sample Topic %02d", i), status: "approved") }

    set_access_mode("gated")

    get topics_path(q: "Capwalk")
    assert_response :success
    page_one = card_names(response.body)

    get topics_path(q: "Capwalk", page: 2)
    assert_response :success
    page_two = card_names(response.body)

    assert_equal 2, page_one.size, "the gated search branch should render exactly two cards"
    # `maintain_derived_fields` normalizes name to lowercase on save.
    assert_equal %w[00 01].map { |n| "capwalk sample topic #{n}" }, page_one
    assert_equal page_one, page_two,
      "?q=&page=2 handed an anonymous visitor a different two topics — the cap is walkable"
  end

  test "signed-in member still gets a real second page of search results" do
    25.times { |i| Topic.create!(name: format("Capwalk Sample Topic %02d", i), status: "approved") }

    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "capwalk-reader@example.com", status: "active"))

    get topics_path(q: "Capwalk")
    page_one = card_names(response.body)

    get topics_path(q: "Capwalk", page: 2)
    page_two = card_names(response.body)

    assert_equal 20, page_one.size
    assert_equal 5, page_two.size
    assert_empty page_one & page_two, "pagination should not repeat topics for a signed-in member"
  end

  test "anonymous visitor gets no cards and no count via turbo_stream, even with a page param" do
    set_access_mode("gated")

    get topics_path(page: 2, format: :turbo_stream)

    assert_response :success
    assert_no_match(/class="topics-card/, response.body)
    assert_no_match(/topics-count/, response.body)
    # The response must be inert: no turbo_stream actions at all, so there
    # is nothing (cards, count, "all topics loaded" copy) for a crafted
    # request to extract.
    assert_no_match(/turbo-stream/, response.body)
  end

  test "signed-in member still gets cards and the count via turbo_stream" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "stream-reader@example.com", status: "active"))

    get topics_path(format: :turbo_stream)

    assert_response :success
    assert_match(/class="topics-card/, response.body)
    assert_match(/topics-count/, response.body)
  end

  private

    # Card identity, in render order, from `<h3 class="topics-card-name">`.
    def card_names(body)
      body.scan(/class="topics-card-name">([^<]*)</).flatten.map(&:strip)
    end

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
