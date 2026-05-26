require "test_helper"

class Scrapers::DiscoverMeetingsCommitteeTest < ActiveSupport::TestCase
  test "Committee.resolve finds by exact name" do
    committee = Committee.create!(name: "City Council")
    assert_equal committee, Committee.resolve("City Council")
  end

  test "Committee.resolve finds by alias" do
    committee = Committee.create!(name: "City Council")
    CommitteeAlias.create!(committee: committee, name: "City Council Meeting")
    assert_equal committee, Committee.resolve("City Council Meeting")
  end

  test "Committee.resolve returns nil for unrecognized body_name" do
    assert_nil Committee.resolve("Totally Unknown Board Meeting")
  end

  test "discovery reuses existing meeting with same time and normalized body name" do
    starts_at = 4.days.from_now.change(usec: 0)
    existing = Meeting.create!(
      body_name: "Plan Commission Meeting",
      meeting_type: "regular",
      starts_at: starts_at,
      status: "upcoming",
      detail_page_url: "https://www.two-rivers.org/bc-pc/page/plan-commission-meeting-112"
    )

    row = Nokogiri::HTML.fragment(<<~HTML).at("tr")
      <tr>
        <td class="views-field-field-calendar-date"><span content="#{starts_at.iso8601}"></span></td>
        <td class="views-field-title">Plan Commission Meeting - Cancelled</td>
        <td class="views-field-view-node"><a href="/bc-pc/page/plan-commission-meeting-113">View Details</a></td>
      </tr>
    HTML

    result = Scrapers::DiscoverMeetingsJob.new.send(:process_row, row, 1.day.ago, enqueue_parse_jobs: false)

    assert_equal existing.id, result
    assert_equal 1, Meeting.where(starts_at: starts_at).count
    assert_equal "https://www.two-rivers.org/bc-pc/page/plan-commission-meeting-112", existing.reload.detail_page_url
    assert_equal "Plan Commission Meeting", existing.body_name
  end

  test "discovery does not mutate an existing meeting when the source reuses a detail URL for a different date" do
    original_starts_at = Time.zone.parse("2026-03-03 08:15:00")
    existing = Meeting.create!(
      body_name: "Personnel and Finance Committee Meeting",
      meeting_type: "regular",
      starts_at: original_starts_at,
      status: "held",
      detail_page_url: "https://www.two-rivers.org/bc-pfc/page/personnel-and-finance-committee-meeting-54"
    )

    row = Nokogiri::HTML.fragment(<<~HTML).at("tr")
      <tr>
        <td class="views-field-field-calendar-date"><span content="2026-05-26T22:30:00Z"></span></td>
        <td class="views-field-title">Personnel and Finance Committee Meeting</td>
        <td class="views-field-view-node"><a href="/bc-pfc/page/personnel-and-finance-committee-meeting-54">View Details</a></td>
      </tr>
    HTML

    result = Scrapers::DiscoverMeetingsJob.new.send(:process_row, row, 1.day.ago, enqueue_parse_jobs: false)

    refute_equal existing.id, result
    assert_equal original_starts_at, existing.reload.starts_at
    assert_equal 2, Meeting.where(body_name: "Personnel and Finance Committee Meeting").count

    new_meeting = Meeting.find(result)
    assert_equal Time.zone.parse("2026-05-26 17:30:00"), new_meeting.starts_at
    assert_equal "https://www.two-rivers.org/bc-pfc/page/personnel-and-finance-committee-meeting-54", new_meeting.detail_page_url
  end
end
