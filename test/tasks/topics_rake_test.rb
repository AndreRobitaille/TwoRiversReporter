require "test_helper"
require "rake"

class TopicsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("topics:seed_category_blocklist")
  end

  test "seed_category_blocklist adds category names to blocklist" do
    TopicBlocklist.where(name: "zoning").destroy_all
    TopicBlocklist.where(name: "infrastructure").destroy_all
    TopicBlocklist.where(name: "finance").destroy_all

    Rake::Task["topics:seed_category_blocklist"].invoke

    assert TopicBlocklist.where(name: "zoning").exists?, "zoning should be blocked"
    assert TopicBlocklist.where(name: "infrastructure").exists?, "infrastructure should be blocked"
    assert TopicBlocklist.where(name: "finance").exists?, "finance should be blocked"
  ensure
    Rake::Task["topics:seed_category_blocklist"].reenable
  end

  test "seed_category_blocklist is idempotent" do
    Rake::Task["topics:seed_category_blocklist"].invoke
    count_after_first = TopicBlocklist.count
    Rake::Task["topics:seed_category_blocklist"].reenable
    Rake::Task["topics:seed_category_blocklist"].invoke
    count_after_second = TopicBlocklist.count

    assert_equal count_after_first, count_after_second
  ensure
    Rake::Task["topics:seed_category_blocklist"].reenable
  end
end
