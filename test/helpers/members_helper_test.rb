require "test_helper"

class MembersHelperTest < ActionView::TestCase
  test "a page direction belongs to the specific finding or agenda item in the cited minutes" do
    url = "https://mccmeetings.blob.core.usgovcloudapi.net/tworivrswi-pubu/MEET-Minutes-bb70d09245c1401c86ded969fc7cdc35.pdf"
    finding = "Make parks accessible to more residents"

    [ { finding: finding }, { agenda_title: "26-088 Paddlers Park" } ].each do |context|
      link = Nokogiri::HTML.fragment(profile_source_link("Council minutes", url, **context)).at_css("a")
      assert_equal "#{url}#page=3", link["href"]
      assert_includes link.text, "item 26-088, pp. 3–4"
    end
    assert_equal link_to("Council minutes", url), profile_source_link("Council minutes", url, agenda_title: "26-089 Sewer lining")
    other_url = "https://example.test/different-minutes.pdf"
    assert_equal link_to("Council minutes", other_url), profile_source_link("Council minutes", other_url, finding: finding)
  end

  test "campaign qualifications omit repeated timing but retain distinct conditions and deadlines" do
    statement = CampaignStatement.new(data: {
      "summary" => "Supports owner occupancy for part of each calendar year.",
      "timeframe" => "per calendar year", "conditions" => "Only if state rules permit it."
    })
    assert_equal [ "Condition: Only if state rules permit it." ], campaign_qualifications(statement)

    statement.data["timeframe"] = "Before the next election."
    assert_equal [ "Condition: Only if state rules permit it.", "Timing: Before the next election." ], campaign_qualifications(statement)

    statement.data["summary"] += " Only if state rules permit it."
    assert_equal [ "Timing: Before the next election." ], campaign_qualifications(statement)
  end
end
