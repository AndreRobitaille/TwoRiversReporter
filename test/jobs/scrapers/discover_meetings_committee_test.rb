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
end
