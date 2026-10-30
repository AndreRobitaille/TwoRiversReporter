require "test_helper"
require Rails.root.join("db/migrate/20261030124500_rename_committee_on_agenda_to_committee_on_aging.rb")

class CommitteeOnAgingCorrectionTest < ActionDispatch::IntegrationTest
  test "repair and rediscovery persist the correct name across resident pages and sharing" do
    travel_to Time.zone.parse("2026-10-30 09:00:00") do
      committee = Committee.create!(name: "Committee on Aging")
      meeting = Meeting.create!(body_name: "Committee On Agenda", starts_at: 3.days.from_now,
        detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda")
      meeting.meeting_summaries.create!(summary_type: "agenda_preview", generation_data: {
        "headline" => "The Committee on Aging will receive reports."
      })
      get meeting_path(meeting)
      assert_response :success
      assert_select "h1", text: "Committee On Agenda"

      RenameCommitteeOnAgendaToCommitteeOnAging.new.migrate(:up)
      assert_equal committee.id, meeting.reload.committee_id
      assert_correct_presentations(meeting)

      row = Nokogiri::HTML.fragment(<<~HTML).at("tr")
        <tr>
          <td class="views-field-field-calendar-date"><span content="#{meeting.starts_at.iso8601}"></span></td>
          <td class="views-field-title">Committee On Agenda</td>
          <td class="views-field-view-node"><a href="/bc-coa/page/committee-agenda">View Details</a></td>
        </tr>
      HTML
      assert_no_difference "Meeting.count" do
        assert_equal meeting.id, Scrapers::DiscoverMeetingsJob.new.send(:process_row, row, 90.days.ago, enqueue_parse_jobs: false)
      end
      assert_correct_presentations(meeting)

      SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
      get meeting_path(meeting)
      assert_response :success
      assert_select "h1", text: "Committee on Aging"
      assert_select 'meta[property="og:title"][content*="Committee on Aging"]'
      assert_select "[data-share-copy-text-value]", count: 0
    end
  end

  private

  def assert_correct_presentations(meeting)
    get meeting_path(meeting)
    assert_response :success
    assert_select "h1", text: "Committee on Aging"
    assert_select "title", text: /Committee on Aging/
    assert_select 'meta[property="og:title"][content*="Committee on Aging"]'
    assert_select 'meta[name="twitter:title"][content*="Committee on Aging"]'
    share = response.parsed_body.at("[data-share-copy-text-value]")
    assert share
    assert_includes share["data-share-copy-text-value"], "Committee on Aging"
    assert_includes share["data-share-facebook-text-value"], "Committee on Aging"
    assert_not_includes response.body, "Committee On Agenda"

    get meetings_path
    assert_response :success
    assert_select "a[href=?] .meetings-card-name", meeting_path(meeting), text: "Committee on Aging"
  end
end
