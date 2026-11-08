require "test_helper"
require_relative "../support/council_service_sources"

class MemberServicePeriodsTest < ActionDispatch::IntegrationTest
  include CouncilServiceSources

  setup do
    @members = %w[Jordan Taylor Morgan].map { |name| Member.create!(name: "#{name} Council") }
    @source = service_source
    @entries = @members.map { |member| { member_id: member.id, started_on: "2024-04-16" } }
  end

  test "one retained packet populates three profiles and unchanged reruns do no work" do
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Service dates do not require AI" }) do
      assert_difference "CouncilServicePeriod.count", 3 do
        record_starts
      end
      original = CouncilServicePeriod.order(:id).pluck(:id, :updated_at)
      travel 1.day do
        assert_no_difference [ "CouncilServicePeriod.count", "MeetingDocumentVersion.count" ] do
          record_starts
        end
      end
      assert_equal original, CouncilServicePeriod.order(:id).pluck(:id, :updated_at)

      @members.each do |member|
        get member_path(member)
        assert_response :success
        assert_select ".member-service-period", count: 1, text: /Term began April 16, 2024/
        assert_select ".member-service-period", text: /May 6|Present|2027/, count: 0
        assert_select ".member-service-period a", text: "Start record, p. 5", count: 1 do |links|
          uri = URI.parse(links.sole["href"])
          assert_equal "page=5", uri.fragment
          uri.fragment = nil
          get uri.to_s
          assert_response :redirect
          follow_redirect!
          assert_response :success
          assert_equal "application/pdf", response.media_type
          assert_equal Rails.root.join("test/fixtures/files/council_service_sample.pdf").binread, response.body
        end
      end
      assert_equal [ @source.id ], CouncilServicePeriod.distinct.pluck(:start_source_version_id)
    end
  end

  test "date correction changes the next request while repeat terms and departures stay distinct" do
    record_starts
    member = @members.first
    original_id = member.council_service_periods.sole.id
    CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: @source, page: 6,
      entries: [ { member_id: member.id, started_on: "2024-04-17" } ])
    assert_equal original_id, member.council_service_periods.reload.sole.id

    previous_source = service_source(date: Date.new(2021, 4, 20))
    member.council_service_periods.create!(period_key: "2021-appointment", started_on: "2021-04-20",
      start_source_version: previous_source, start_page: 1, ended_on: "2023-08-01",
      end_source_version: @source, end_page: 2)
    get member_path(member)
    rows = css_select(".member-service-period")
    assert_equal 2, rows.size
    assert_match "Term began April 17, 2024", rows.first.text
    assert_match "April 20, 2021 – August 1, 2023", rows.last.text.squish
    assert_select ".member-service-period a", text: "End record, p. 2", count: 1

    SiteSetting.create!(access_mode: "gated", singleton_guard: 0)
    get member_path(member)
    assert_select ".member-service-period", count: 2
    assert_equal "private, no-store", response.headers["Cache-Control"]
  end

  test "current titles and attendance cannot manufacture a Council service period" do
    member = @members.first
    member.member_positions.create!(kind: "city_manager", title: "City Manager", source: "admin_manual",
      source_url: "https://example.test/roster", verified_at: Time.current)
    get member_path(member)
    assert_select ".member-article-header .badge", text: "City Manager"
    assert_select ".member-service-periods", count: 0
  end

  private

  def record_starts
    CouncilServicePeriod.record_starts!(period_key: "2024-election", source_version: @source, page: 5, entries: @entries)
  end
end
