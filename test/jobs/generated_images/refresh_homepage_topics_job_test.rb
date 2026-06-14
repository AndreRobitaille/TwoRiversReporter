require "test_helper"

class GeneratedImages::RefreshHomepageTopicsJobTest < ActiveJob::TestCase
  test "enqueues generate job for homepage topics with briefing headline" do
    topic = Topic.create!(name: "Eligible Topic", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 1.day.ago)
    TopicBriefing.create!(topic: topic, headline: "Headline", generation_tier: "full")

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::HomepageTopicSelector.stub :new, -> { Object.new.tap { |selector| selector.define_singleton_method(:call) { [ topic ] } } } do
        assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ topic.id ]) do
          GeneratedImages::RefreshHomepageTopicsJob.perform_now
        end
      end
    end
  end

  test "skips topics without briefing headline" do
    topic = Topic.create!(name: "Missing Briefing", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 1.day.ago)

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::HomepageTopicSelector.stub :new, -> { Object.new.tap { |selector| selector.define_singleton_method(:call) { [ topic ] } } } do
        assert_no_enqueued_jobs only: GeneratedImages::GenerateForTopicJob do
          GeneratedImages::RefreshHomepageTopicsJob.perform_now
        end
      end
    end
    assert true
  end

  test "returns when disabled" do
    GeneratedImages::Config.stub :enabled?, false do
      GeneratedImages::RefreshHomepageTopicsJob.perform_now
      assert true
    end
  end

  test "uses recurring-friendly default queue path" do
    assert_equal "default", GeneratedImages::RefreshHomepageTopicsJob.queue_name
  end
end
