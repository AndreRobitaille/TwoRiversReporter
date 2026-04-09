require "test_helper"
require "rake"

class BackfillStatusRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("backfill:status")
    Rake::Task["backfill:status"].reenable
  end

  test "backfill:status runs without error and prints meeting counts" do
    # Create a meeting in the backfill window
    Meeting.create!(
      detail_page_url: "https://two-rivers.org/meetings/test-1",
      starts_at: Date.new(2025, 6, 15),
      body_name: "City Council"
    )

    output = capture_io { Rake::Task["backfill:status"].invoke }.first

    assert_match(/Meetings since 2025-01-01/, output)
    assert_match(/Total meetings/, output)
  end

  test "backfill:status shows zero counts when no meetings exist" do
    output = capture_io { Rake::Task["backfill:status"].invoke }.first

    assert_match(/Total meetings:\s+0/, output)
  end
end
