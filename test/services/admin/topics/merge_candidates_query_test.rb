require "test_helper"

module Admin
  module Topics
    class MergeCandidatesQueryTest < ActiveSupport::TestCase
      test "returns matching topics excluding the current topic with reasons" do
        current = Topic.create!(name: "lakeshore community foundation partnership", status: "approved")
        exact = Topic.create!(name: "lakeshore community foundation", status: "approved")
        TopicAlias.create!(topic: exact, name: "lakeshore foundation")
        description_match = Topic.create!(name: "zeta community grants", status: "approved", description: "Lakeshore community foundation cleanup")

        results = Admin::Topics::MergeCandidatesQuery.new(topic: current, query: "lakeshore community").call

        refute_includes results.map(&:topic_id), current.id
        assert_equal [ exact.id, description_match.id ], results.map(&:topic_id)
        assert_equal "name matches search", results.first.match_reason
        assert_match(/description/i, results.last.match_reason)
      end
    end
  end
end
