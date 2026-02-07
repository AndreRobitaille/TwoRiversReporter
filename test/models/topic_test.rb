require "test_helper"

class TopicTest < ActiveSupport::TestCase
  setup do
    Topic.destroy_all
  end

  test "normalizes name on create" do
    topic = Topic.create!(name: "  Foo Bar!  ")
    assert_equal "foo bar", topic.name
  end

  test "publicly_visible scope" do
    Topic.create!(name: "approved", status: "approved")
    Topic.create!(name: "pinned", pinned: true, status: "proposed")
    Topic.create!(name: "blocked", status: "blocked")
    Topic.create!(name: "proposed", status: "proposed")

    assert_equal 2, Topic.publicly_visible.count
    assert_includes Topic.publicly_visible.map(&:name), "approved"
    assert_includes Topic.publicly_visible.map(&:name), "pinned"
  end
end
