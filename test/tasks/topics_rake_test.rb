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

  test "mark_unsafe_for_reuse updates matching topics from TOPICS env" do
    redevelopment = Topic.create!(name: "Redevelopment", reuse_strategy: "canonical")
    community_visioning = Topic.create!(name: "Community Visioning", reuse_strategy: "canonical")

    previous_topics = ENV["TOPICS"]
    ENV["TOPICS"] = "redevelopment,community visioning"

    Rake::Task["topics:mark_unsafe_for_reuse"].invoke

    assert_equal "unsafe_for_auto_reuse", redevelopment.reload.reuse_strategy
    assert_equal "unsafe_for_auto_reuse", community_visioning.reload.reuse_strategy
  ensure
    ENV["TOPICS"] = previous_topics
    Rake::Task["topics:mark_unsafe_for_reuse"].reenable
  end
end
