require "test_helper"

class Topics::AgendaBriefingContextTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "Synthetic marsh access proposal", status: "approved", resident_impact_score: 4)
    @briefing = @topic.create_topic_briefing!(headline: "Synthetic supported marsh context",
      editorial_content: "Synthetic retained interpretation", upcoming_headline: "Synthetic next meeting", generation_tier: "full")
  end

  test "six highest ranked distinct topics and bounded excerpts retain alias matching" do
    @topic.topic_aliases.create!(name: "Synthetic riverfront boat launch")
    @briefing.update!(editorial_content: "z" * 1200 + "Synthetic clipped tail")
    others = 7.times.map do |index|
      topic = Topic.create!(name: "Synthetic riverfront boat launch #{('a'.ord + index).chr}", status: "approved", resident_impact_score: 3)
      topic.create_topic_briefing!(headline: "Synthetic headline #{index}", editorial_content: "Synthetic text", generation_tier: "full")
      topic
    end
    context = Topics::AgendaBriefingContext.new("Synthetic riverfront boat launches")
    names = context.text.scan(/^## Known topic: (.+)$/).flatten
    assert_equal [ @topic.name ] + others.first(5).map(&:name), names
    assert_equal 6, names.uniq.size
    assert_includes context.text, "z" * 1197 + "..."
    refute_includes context.text, "Synthetic clipped tail"
    assert_equal :saved, context.with_current { :saved }
    @topic.topic_aliases.destroy_all
    assert_nil context.with_current { flunk "A consumed alias no longer matches the agenda" }
  end

  test "changes to every consumed field or eligibility prevent publication" do
    [
      -> { @briefing.update!(editorial_content: "Synthetic revised interpretation") },
      -> { @briefing.update!(upcoming_headline: "Synthetic revised next step") },
      -> { @topic.update!(status: "proposed") },
      -> { @topic.update!(resident_impact_score: 2) },
      -> { @topic.update!(name: "Synthetic unrelated sewer proposal") },
      -> { @briefing.destroy! }
    ].each do |change|
      Topic.transaction(requires_new: true) do
        context = Topics::AgendaBriefingContext.new(@topic.name)
        assert_includes context.text, @briefing.headline
        assert_equal :saved, context.with_current { :saved }
        change.call
        assert_nil context.with_current { flunk "Changed context must not publish" }
        raise ActiveRecord::Rollback
      end
      @topic.reload
      @briefing = @topic.reload.topic_briefing
    end
  end

  test "new optional context and changes beyond the consumed excerpt do not invalidate the snapshot" do
    @briefing.update!(editorial_content: "z" * 1300)
    context = Topics::AgendaBriefingContext.new(@topic.name)
    @briefing.update!(editorial_content: "z" * 1300 + "New unconsumed tail")
    another = Topic.create!(name: "Synthetic marsh access improvements", status: "approved", resident_impact_score: 5)
    another.create_topic_briefing!(headline: "Synthetic optional new context", editorial_content: "New interpretation", generation_tier: "full")
    assert_equal :saved, context.with_current { :saved }
    refute_includes context.text, another.topic_briefing.headline
  end

  test "empty topic context does not obstruct an agenda-only publication" do
    context = Topics::AgendaBriefingContext.new("Roll call")
    assert_empty context.text
    assert_equal :saved, context.with_current { :saved }
  end
end
