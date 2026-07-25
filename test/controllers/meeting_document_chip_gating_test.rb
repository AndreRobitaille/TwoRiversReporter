require "test_helper"

# The document chips at the top of meeting show (Minutes/Agenda/Packet/City
# Website/Watch Recording) and the Share control used to carry a working
# `href`/payload no matter the access mode — a gated visitor could click
# straight through to the official PDF (or YouTube recording), defeating the
# teaser tier entirely. This pins the fix: for a gated anonymous visitor the
# chips render (so a visitor can see which documents exist) but carry no URL
# anywhere in the response, and the Share control emits no copy/Facebook
# payload and no dropdown actions.
class MeetingDocumentChipGatingTest < ActionDispatch::IntegrationTest
  BLOB_HOST = "mccmeetings.blob.core.usgovcloudapi.net".freeze

  MINUTES_URL = "https://#{BLOB_HOST}/tworivrswi-pubu/MEET-Minutes-canary.pdf".freeze
  AGENDA_URL = "https://#{BLOB_HOST}/tworivrswi-pubu/MEET-Agenda-canary.pdf".freeze
  PACKET_URL = "https://#{BLOB_HOST}/tworivrswi-pubu/MEET-Packet-canary.pdf".freeze
  CITY_WEBSITE_URL = "https://example.com/city-website-canary".freeze
  TRANSCRIPT_URL = "https://www.youtube.com/watch?v=canaryVideoId1".freeze

  setup do
    @meeting = Meeting.create!(
      body_name: "City Council Meeting",
      starts_at: 3.days.ago,
      detail_page_url: CITY_WEBSITE_URL
    )
    @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: MINUTES_URL)
    @meeting.meeting_documents.create!(document_type: "agenda_pdf", source_url: AGENDA_URL)
    @meeting.meeting_documents.create!(document_type: "packet_pdf", source_url: PACKET_URL)
    @meeting.meeting_documents.create!(document_type: "transcript", source_url: TRANSCRIPT_URL)
    @meeting.meeting_summaries.create!(
      summary_type: "minutes_recap",
      generation_data: {
        "headline" => "Council approved the Washington Street reconstruction contract after a lengthy discussion of funding sources.",
        "highlights" => [ { "text" => "Council approved the contract on a 6-1 vote after debate." } ]
      }
    )
  end

  test "gated anonymous visitor: no document URL reaches the response body" do
    set_access_mode("gated")

    get meeting_path(@meeting)
    assert_response :success

    # This is the assertion that matters: grep the raw body, not a parsed
    # link list, so it also catches a URL smuggled into a data-* attribute,
    # a comment, or inline JSON.
    assert_no_match(/#{Regexp.escape(BLOB_HOST)}/, response.body,
      "the blob-storage host must not appear anywhere in the response")
    assert_no_match(/#{Regexp.escape(CITY_WEBSITE_URL)}/, response.body,
      "the City Website URL must not appear anywhere in the response")
    assert_no_match(/youtube\.com\/watch/, response.body,
      "the YouTube recording URL must not appear anywhere in the response")
  end

  test "gated anonymous visitor: chip labels still identify which documents exist" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_select ".meeting-article-docs", text: /Minutes/
    assert_select ".meeting-article-docs", text: /Agenda/
    assert_select ".meeting-article-docs", text: /Packet/
    assert_select ".meeting-article-docs", text: /City Website/
    assert_select ".meeting-article-docs", text: /Watch Recording/
  end

  test "gated anonymous visitor: document chips render as non-anchor, non-focusable elements" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_select ".meeting-article-docs a[href]", false,
      "no anchor with an href should exist among the document chips"
    assert_select ".meeting-doc-link--disabled", minimum: 5
    assert_select "span.meeting-doc-link--disabled[tabindex]", false,
      "disabled chips must not be made focusable"
  end

  test "gated anonymous visitor: Share control emits no payload and no dropdown actions" do
    set_access_mode("gated")

    get meeting_path(@meeting)

    assert_select ".share-wrapper", false
    assert_select ".share-dropdown", false
    assert_select "[data-action='share#copy']", false
    assert_select "[data-action='share#facebook']", false
    assert_no_match(/data-share-/, response.body,
      "no data-share-*-value attribute may be emitted for a gated visitor")

    # The affordance stays legible: a visibly disabled Share button.
    assert_select "button.meeting-doc-link--share[disabled]", text: /Share/
  end

  test "signed-in member: real hrefs and the working share control are unchanged" do
    set_access_mode("gated")
    sign_in_as(User.create!(email_address: "chip-reader@example.com", status: "active"))

    get meeting_path(@meeting)
    assert_response :success

    assert_select ".meeting-article-docs a[href='#{MINUTES_URL}']", text: /Minutes/
    assert_select ".meeting-article-docs a[href='#{AGENDA_URL}']", text: /Agenda/
    assert_select ".meeting-article-docs a[href='#{PACKET_URL}']", text: /Packet/
    assert_select ".meeting-article-docs a[href='#{CITY_WEBSITE_URL}']", text: /City Website/
    assert_select ".meeting-article-docs a[href='#{TRANSCRIPT_URL}']", text: /Watch Recording/

    wrapper = css_select(".share-wrapper").first
    assert wrapper, "the working share control must render for a signed-in member"
    assert wrapper["data-share-copy-text-value"].present?
    assert_select ".share-dropdown-item", count: 2
    assert_select ".meeting-doc-link--disabled", false
  end

  test "open mode: real hrefs and the working share control are unchanged for anonymous visitors" do
    set_access_mode("open")

    get meeting_path(@meeting)
    assert_response :success

    assert_select ".meeting-article-docs a[href='#{MINUTES_URL}']", text: /Minutes/
    assert_select ".meeting-article-docs a[href='#{AGENDA_URL}']", text: /Agenda/
    assert_select ".meeting-article-docs a[href='#{PACKET_URL}']", text: /Packet/
    assert_select ".meeting-article-docs a[href='#{CITY_WEBSITE_URL}']", text: /City Website/
    assert_select ".meeting-article-docs a[href='#{TRANSCRIPT_URL}']", text: /Watch Recording/

    wrapper = css_select(".share-wrapper").first
    assert wrapper, "the working share control must render in open mode"
    assert wrapper["data-share-copy-text-value"].present?
    assert_select ".share-dropdown-item", count: 2
    assert_select ".meeting-doc-link--disabled", false
  end

  private

    def set_access_mode(mode)
      SiteSetting.delete_all
      SiteSetting.create!(access_mode: mode, singleton_guard: 0)
    end
end
