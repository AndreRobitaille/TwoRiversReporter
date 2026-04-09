require "test_helper"
require "rake"

class BackfillRunRakeTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("backfill:run")
    Rake::Task["backfill:run"].reenable
  end

  test "backfill:run enqueues DiscoverMeetingsJob with since 2025-01-01" do
    assert_enqueued_with(job: Scrapers::DiscoverMeetingsJob) do
      Rake::Task["backfill:run"].invoke
    end
  end
end
