require "test_helper"

module Topics
  class PromoteAliasServiceTest < ActiveSupport::TestCase
    test "promotes alias into a standalone topic" do
      topic = Topic.create!(name: "water main break")
      alias_record = TopicAlias.create!(topic: topic, name: "water main breaks")

      promoted_topic = PromoteAliasService.new(topic_alias: alias_record).call

      assert_equal "water main breaks", promoted_topic.name
      assert Topic.exists?(topic.id)
      assert_not TopicAlias.exists?(alias_record.id)
      assert_equal 0, topic.reload.topic_aliases.count
    end

    test "records a review event when a user is present" do
      user = User.create!(email_address: "admin@example.com", password: "password", admin: true)
      Current.session = Struct.new(:user).new(user)
      topic = Topic.create!(name: "water main break")
      alias_record = TopicAlias.create!(topic: topic, name: "water main breaks")

      assert_difference -> { TopicReviewEvent.where(action: "alias_promoted").count }, 1 do
        PromoteAliasService.new(topic_alias: alias_record).call
      end

      promoted = Topic.find_by!(name: "water main breaks")
      event = TopicReviewEvent.find_by!(action: "alias_promoted")

      assert_equal promoted, event.topic
    ensure
      Current.reset
    end

    test "persists promotion reason" do
      user = User.create!(email_address: "admin@example.com", password: "password", admin: true)
      Current.session = Struct.new(:user).new(user)
      topic = Topic.create!(name: "water main break")
      alias_record = TopicAlias.create!(topic: topic, name: "water main breaks")

      PromoteAliasService.new(topic_alias: alias_record, reason: "promoted during cleanup").call

      assert_equal "promoted during cleanup", TopicReviewEvent.find_by!(action: "alias_promoted").reason
    ensure
      Current.reset
    end
  end
end
