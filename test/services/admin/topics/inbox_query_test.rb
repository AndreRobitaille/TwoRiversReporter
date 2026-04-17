require "test_helper"

module Admin
  module Topics
    class InboxQueryTest < ActiveSupport::TestCase
      test "orders results by most recently updated first even when scope is preordered" do
        older = Topic.create!(name: "alpha", status: "proposed", review_status: "proposed", updated_at: 2.days.ago)
        newer = Topic.create!(name: "zulu", status: "proposed", review_status: "proposed", updated_at: 1.day.ago)

        scope = Topic.where(id: [ older.id, newer.id ]).order(:name)

        rows = Admin::Topics::InboxQuery.new(scope: scope).call

        assert_equal [ newer.id, older.id ], rows.map(&:topic_id)
      end

      test "returns flagged topics with compact metadata" do
        proposed = Topic.create!(name: "uncertain sidewalk funding", status: "proposed", review_status: "proposed")
        blocked = Topic.create!(name: "public hearing", status: "blocked", review_status: "blocked")
        approved = Topic.create!(name: "approved project", status: "approved", review_status: "approved")
        TopicAlias.create!(topic: blocked, name: "public hearings")

        rows = Admin::Topics::InboxQuery.new(scope: Topic.where(review_status: %w[proposed blocked approved])).call.to_a

        assert_includes rows.map(&:topic_id), proposed.id
        assert_includes rows.map(&:topic_id), approved.id
        blocked_row = rows.find { |row| row.topic_id == blocked.id }
        assert_equal 1, blocked_row.alias_count
        assert_respond_to blocked_row, :reason_label
      end

      test "sorts by alias count when requested" do
        low = Topic.create!(name: "low alias #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
        high = Topic.create!(name: "high alias #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
        2.times { |index| TopicAlias.create!(topic: high, name: "high alias alt #{index} #{SecureRandom.hex(2)}") }

        rows = Admin::Topics::InboxQuery.new(scope: Topic.where(id: [ low.id, high.id ]), sort: "alias_count").call

        assert_equal [ high.id, low.id ], rows.map(&:topic_id)
      end

      test "builds useful visual signals" do
        topic = Topic.create!(
          name: "signal topic #{SecureRandom.hex(4)}",
          status: "approved",
          review_status: "approved",
          pinned: true,
          lifecycle_status: "dormant"
        )

        row = Admin::Topics::InboxQuery.new(scope: Topic.where(id: topic.id)).call.first

        assert_includes row.signals, "Pinned"
        assert_includes row.signals, "No description"
        assert_includes row.signals, "Zero mentions"
        assert_includes row.signals, "Dormant"
      end

      test "includes alias names for row display" do
        topic = Topic.create!(name: "alias topic #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
        TopicAlias.create!(topic: topic, name: "alias one #{SecureRandom.hex(2)}")
        TopicAlias.create!(topic: topic, name: "alias two #{SecureRandom.hex(2)}")

        row = Admin::Topics::InboxQuery.new(scope: Topic.where(id: topic.id)).call.first

        assert_equal 2, row.alias_names.size
        assert_match /alias one/i, row.alias_names.first
      end
    end
  end
end
