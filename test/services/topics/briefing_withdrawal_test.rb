require "test_helper"
require_relative "../../support/briefing_withdrawal_scenario"

class Topics::BriefingWithdrawalTest < ActiveJob::TestCase
  include BriefingWithdrawalScenario

  setup { build_withdrawal_scenario }

  test "same identity review leaves supported briefing intact and replay does not change a withdrawal" do
    original = @briefing.attributes
    observation = @event.decision_observation
    review = CouncilDecisions::ResolveIdentity.call(observation: observation, action: "assign", actor: @actor,
      reason: "Confirm existing synthetic identity", expected_correction_id: nil, request_id: SecureRandom.uuid,
      decision: @event.council_decision, basis_observation: observation)
    assert_equal original, @briefing.reload.attributes
    args = { observation: observation, action: "unassign", actor: @actor, reason: "Synthetic withdrawal",
      expected_correction_id: review.id, request_id: SecureRandom.uuid }
    without_paid_providers do
      assert_no_enqueued_jobs { CouncilDecisions::ResolveIdentity.call(**args) }
      withdrawn = @briefing.reload.attributes
      assert_not_nil withdrawn["evidence_withdrawn_at"]
      assert_no_difference "CouncilDecisionCorrection.count" do
        CouncilDecisions::ResolveIdentity.call(**args)
      end
      assert_equal withdrawn, @briefing.reload.attributes
    end
  end

  test "withdrawal and correction roll back together when dependent update fails" do
    original = @briefing.attributes
    identity = @event.council_decision.id
    service = Topics::WithdrawCorrectedBriefings.method(:call)
    Topics::WithdrawCorrectedBriefings.stub(:call, ->(**args) { service.call(**args); raise "Synthetic transaction interruption" }) do
      assert_no_difference "CouncilDecisionCorrection.count" do
        assert_raises(RuntimeError) { withdraw_decision }
      end
    end
    assert_equal original, @briefing.reload.attributes
    assert_equal identity, @event.reload.council_decision.id
  end

  test "fresh full generation restores publication while partial updates cannot clear withdrawal" do
    withdraw_decision
    withdrawn = @briefing.reload.attributes
    without_paid_providers do
      %w[headline_only interim].each do |tier|
        Topics::UpdateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id, tier: tier)
      end
    end
    assert_equal withdrawn, @briefing.reload.attributes
    @provider.define_singleton_method(:analyze_topic_briefing) do |context, **|
      { headline: "Synthetic corrected identity remains unresolved", editorial_analysis: { current_state: "Synthetic replacement analysis" } }.to_json
    end
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id) }
    published = @topic.reload.published_topic_briefing
    assert_not_nil published
    assert_equal @briefing.id, published.id
    assert_equal "Synthetic corrected identity remains unresolved", published.headline
    assert_nil published.withdrawal_correction_id
    events = published.generation_data.fetch("evidence_manifest").fetch("motion_evidence")
    assert_nil events.find { |entry| entry["event_id"] == @event.id }.dig("reference", "decision_public_id")
    without_paid_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id) }
    assert_equal published.attributes, @briefing.reload.attributes
  end

  test "correction during briefing rendering leaves the old analysis withdrawn" do
    @agenda.update!(summary: "Synthetic new context requires generation")
    retained = @briefing.generation_data.deep_dup
    review = method(:withdraw_decision)
    @provider.define_singleton_method(:render_topic_briefing) do |*, **|
      review.call
      { "editorial_content" => "A stale synthetic replacement", "record_content" => "Stale record" }
    end
    withdrawal_providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id) }
    assert_nil @topic.reload.published_topic_briefing
    assert_equal retained, @briefing.reload.generation_data
    refute_equal "A stale synthetic replacement", @briefing.editorial_content
  end

  test "correction supersedes retained illustration and rejects a delayed generated image" do
    old_image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", source_briefing: @briefing)
    old_image.file.attach(io: StringIO.new("retained synthetic image bytes"), filename: "old.jpg", content_type: "image/jpeg")
    assert_equal old_image, @topic.current_generated_image(:og)
    review = method(:withdraw_decision)
    image_provider = Object.new
    image_provider.define_singleton_method(:build_generated_image_brief) { |*| { "civic_issue" => "Synthetic cedar improvements" } }
    image_provider.define_singleton_method(:generate_civic_image) do |**|
      review.call
      { bytes: "late synthetic image bytes", format: "jpeg", size: "1536x1024", model: "deterministic-fixture" }
    end
    result = GeneratedImages::Generator.new(@topic, source: @briefing, ai_service: image_provider).call
    assert_equal "superseded", result.reload.status
    refute result.file.attached?
    assert_equal "superseded", old_image.reload.status
    assert old_image.file.attached?, "Retain the historical artifact without republishing it"
    assert_nil @topic.reload.current_generated_image(:og)
    without_paid_providers do
      assert_no_difference "GeneratedImage.count" do
        GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
      end
    end
  end

  test "delayed interim note cannot contaminate a restored full briefing" do
    @provider.define_singleton_method(:analyze_topic_briefing) do |*, **|
      { headline: "Synthetic restored briefing", editorial_analysis: { current_state: "Synthetic corrected story" } }.to_json
    end
    restore = -> do
      withdraw_decision
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
    end
    @provider.define_singleton_method(:generate_briefing_interim) do |*|
      restore.call
      { "headline" => "Stale synthetic headline", "upcoming_note" => "Stale synthetic interim assertion" }
    end
    withdrawal_providers do
      Topics::UpdateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id, tier: "interim")
    end
    published = @topic.reload.published_topic_briefing
    assert_equal "Synthetic corrected story", published.editorial_content
    refute_equal "Stale synthetic headline", published.upcoming_headline
  end

  test "legacy briefing without a dependency receipt is not assigned invented provenance" do
    legacy = @other_briefing.generation_data.except("evidence_manifest")
    @other_briefing.update!(generation_data: legacy)
    withdraw_decision
    assert_equal legacy, @other.reload.published_topic_briefing.generation_data
  end
end
