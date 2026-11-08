require "test_helper"

class MembersHelperTest < ActionView::TestCase
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
