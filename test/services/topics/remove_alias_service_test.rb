require "test_helper"

module Topics
  class RemoveAliasServiceTest < ActiveSupport::TestCase
    test "removes alias without deleting topic" do
      topic = Topic.create!(name: "water main break")
      alias_record = TopicAlias.create!(topic: topic, name: "water-main break")

      assert_difference -> { TopicAlias.count }, -1 do
        RemoveAliasService.new(topic_alias: alias_record).call
      end

      assert Topic.exists?(topic.id)
    end

    test "records a review event when a user is present" do
      user = User.create!(email_address: "admin@example.com", password: "password", admin: true)
      Current.session = Struct.new(:user).new(user)
      topic = Topic.create!(name: "water main break")
      alias_record = TopicAlias.create!(topic: topic, name: "water-main break")

      assert_difference -> { TopicReviewEvent.where(action: "alias_removed").count }, 1 do
        RemoveAliasService.new(topic_alias: alias_record).call
      end
    ensure
      Current.reset
    end

    test "persists removal reason" do
      user = User.create!(email_address: "admin@example.com", password: "password", admin: true)
      Current.session = Struct.new(:user).new(user)
      topic = Topic.create!(name: "water main break")
      alias_record = TopicAlias.create!(topic: topic, name: "water-main break")

      RemoveAliasService.new(topic_alias: alias_record, reason: "duplicate spelling").call

      assert_equal "duplicate spelling", TopicReviewEvent.find_by!(action: "alias_removed").reason
    ensure
      Current.reset
    end
  end
end
