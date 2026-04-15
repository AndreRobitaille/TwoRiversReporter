require "test_helper"

class MeetingSummaryTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: 1.day.ago,
      detail_page_url: "http://example.com/meeting"
    )
  end

  test "accepts agenda_preview as summary_type" do
    summary = MeetingSummary.new(meeting: @meeting, summary_type: "agenda_preview")
    assert summary.valid?, "agenda_preview should be a valid summary_type, errors: #{summary.errors.full_messages}"
  end

  test "rejects unknown summary_type" do
    summary = MeetingSummary.new(meeting: @meeting, summary_type: "bogus_type")
    refute summary.valid?
    assert_includes summary.errors[:summary_type].join, "included"
  end
end
