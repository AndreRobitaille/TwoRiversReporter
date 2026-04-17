require "test_helper"

module Admin
  module Topics
    class DetailWorkspaceQueryTest < ActiveSupport::TestCase
      test "builds header counts and recent activity for repair workspace" do
        topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved", pinned: true)
        TopicAlias.create!(topic: topic, name: "harbor project")
        TopicAlias.create!(topic: topic, name: "dredging harbor")
        TopicAlias.create!(topic: topic, name: "harbor works")
        TopicReviewEvent.create!(topic: topic, action: "merged", reason: "duplicate cleanup")
        meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 2.days.from_now, status: "scheduled", detail_page_url: "https://example.com")
        agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Dredging", order_index: 1)
        AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)
        motion = Motion.create!(meeting: meeting, agenda_item: agenda_item)
        second_motion = Motion.create!(meeting: meeting, agenda_item: agenda_item)
        member = Member.create!(name: "Council Member")
        Vote.create!(motion: motion, member: member, value: "yes")
        Vote.create!(motion: second_motion, member: Member.create!(name: "Council Member 2"), value: "no")
        topic.update!(last_seen_at: 3.days.ago, last_activity_at: 1.day.ago)

        workspace = DetailWorkspaceQuery.new(topic: topic).call

        assert_equal topic, workspace.topic
        assert_equal 3, workspace.aliases.size
        assert_equal 1, workspace.recent_history.size
        assert_equal true, workspace.pinned
        assert_equal 1, workspace.appearance_count
        assert_equal 3, workspace.alias_count
        assert_equal 0, workspace.summary_count
        assert_equal 2, workspace.decision_count
        assert_equal 2, workspace.vote_count
        assert_equal 1, workspace.future_appearance_count
        assert_in_delta 3.days.ago.to_i, workspace.last_seen_at.to_i, 5
        assert_in_delta 1.day.ago.to_i, workspace.last_activity_at.to_i, 5
        assert_includes workspace.signals, "Pinned"
      end

      test "adds basic problem signals for blocked proposed and alias heavy topics" do
        topic = Topic.create!(name: "harbor dredging", status: "blocked", review_status: "proposed")
        3.times { |i| TopicAlias.create!(topic: topic, name: "alias #{i}") }

        workspace = DetailWorkspaceQuery.new(topic: topic).call

        assert_includes workspace.signals, "Needs review"
        assert_includes workspace.signals, "Blocked"
        assert_includes workspace.signals, "Alias-heavy"
      end
    end
  end
end
