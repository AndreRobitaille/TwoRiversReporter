require "test_helper"

# The About page argues that public-but-unreadable information is an access
# problem. In gated mode a stranger reads that argument and then hits an access
# problem, so several passages are swapped and a gated-only "Getting Access"
# section is added. These tests pin both halves of that swap: the gated copy
# appears and the open copy does not, and vice versa.
class AboutGatingTest < ActionDispatch::IntegrationTest
  # Phrases that exist only in the open-mode copy. Each one implicitly promises
  # the reader access they do not have when gated.
  OPEN_DEK_PROMISE = "to help you understand what's actually happening at city hall".freeze
  OPEN_THESIS_PROMISE = "It reads the documents so you don't have to.".freeze
  OPEN_ACCOUNTABILITY_PROMISE = "The city does its job, and residents get to see how it's going.".freeze
  OPEN_PIPELINE_PROMISE = "You get what the city's website doesn't give you.".freeze

  ALL_OPEN_PHRASES = [
    OPEN_DEK_PROMISE,
    OPEN_THESIS_PROMISE,
    OPEN_ACCOUNTABILITY_PROMISE,
    OPEN_PIPELINE_PROMISE
  ].freeze

  # Phrases that exist only in the gated copy.
  GATED_ACCESS_FACT = "Access to this site is by approval.".freeze
  GATED_RECORDS_CAVEAT = "The city's own records are not behind this.".freeze
  GATED_THESIS = "Reading that work is currently by approval".freeze

  test "gated anonymous visitor sees the Getting Access section" do
    set_access_mode("gated")

    get about_path

    assert_response :success
    assert_select "section#getting-access"
    assert_select "section#getting-access .section-label", text: "Getting Access"
    assert_match(/#{Regexp.escape(GATED_ACCESS_FACT)}/, response.body)
    assert_match(/#{Regexp.escape(GATED_RECORDS_CAVEAT)}/, response.body)
  end

  test "gated anonymous visitor is given a link to the application" do
    set_access_mode("gated")

    get about_path

    assert_response :success
    assert_select "section#getting-access a[href=?]", new_application_path
  end

  test "gated anonymous visitor can reach the access section from the anchor bar" do
    set_access_mode("gated")

    get about_path

    assert_response :success
    assert_select ".about-anchor-bar a[href='#getting-access']"
  end

  test "gated anonymous visitor never sees the open-mode access promises" do
    set_access_mode("gated")

    get about_path

    assert_response :success
    ALL_OPEN_PHRASES.each do |phrase|
      assert_no_match(/#{Regexp.escape(phrase)}/, response.body,
        "gated About page still contains the open-mode promise: #{phrase}")
    end
  end

  test "gated anonymous visitor still gets the diagnosis the whole page rests on" do
    set_access_mode("gated")

    get about_path

    assert_response :success
    # The diagnosis survives the rewrite; only the unconditional promise goes.
    assert_match(/it's not practically accessible/, response.body)
    assert_match(/This site exists to close that gap/, response.body)
    assert_match(/#{Regexp.escape(GATED_THESIS)}/, response.body)
  end

  test "signed-in member in gated mode sees the original open-mode copy" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "about-member@example.com", status: "active"))

    get about_path

    assert_response :success
    ALL_OPEN_PHRASES.each do |phrase|
      assert_match(/#{Regexp.escape(phrase)}/, response.body,
        "signed-in member is missing the open-mode copy: #{phrase}")
    end
  end

  test "signed-in member in gated mode does not see the Getting Access section" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "about-member-2@example.com", status: "active"))

    get about_path

    assert_response :success
    assert_select "section#getting-access", count: 0
    assert_select ".about-anchor-bar a[href='#getting-access']", count: 0
    assert_no_match(/#{Regexp.escape(GATED_ACCESS_FACT)}/, response.body)
  end

  test "open mode shows the original copy to anonymous visitors" do
    set_access_mode("open")

    get about_path

    assert_response :success
    ALL_OPEN_PHRASES.each do |phrase|
      assert_match(/#{Regexp.escape(phrase)}/, response.body,
        "open-mode About page is missing: #{phrase}")
    end
  end

  test "open mode hides the Getting Access section from anonymous visitors" do
    set_access_mode("open")

    get about_path

    assert_response :success
    assert_select "section#getting-access", count: 0
    assert_select ".about-anchor-bar a[href='#getting-access']", count: 0
    assert_no_match(/#{Regexp.escape(GATED_ACCESS_FACT)}/, response.body)
  end

  test "About is a public page and returns 200 anonymously in both modes" do
    %w[open gated].each do |mode|
      set_access_mode(mode)

      get about_path

      assert_response :success, "About page did not return 200 anonymously in #{mode} mode"
      # Explicitly not a redirect: access mode must never gate the page itself.
      assert_no_match(/<html[^>]*>\s*<head[^>]*>\s*<title>Redirect/, response.body)
      assert_select "h1", text: /Your City Hall/
    end
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
