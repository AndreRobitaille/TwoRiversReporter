require "test_helper"
require "minitest/mock"
require "open-uri"

class Topics::GenerationEvidenceTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Synthetic civic improvements", status: "approved")
    @calls, @summary_inputs, @briefing_inputs = [], [], []
    @hooks, @claims = {}, {}
    @meeting, @document, @agenda = add_meeting("garden", "Retained synthetic garden decision", 2.days.ago)
    build_providers
  end

  test "completed briefing reuses identical local evidence without retrieval or generation" do
    summarize(@meeting)
    briefing
    stored = @topic.reload.topic_briefing.attributes
    assert @topic.topic_briefing.generation_data["evidence_manifest"], "Published output needs a trusted dependency receipt"
    Ai::OpenAiService.stub :new, ->(*) { flunk "Unchanged briefing must not construct a generation provider" } do
      RetrievalService.stub :new, ->(*) { flunk "Unchanged briefing must not request an embedding" } do
        Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      end
    end
    assert_equal stored, @topic.reload.topic_briefing.attributes
  end

  test "repeated full meeting workflow reuses its unchanged topic stage" do
    summarize(@meeting)
    original = @meeting.topic_summaries.sole.attributes
    @calls.clear
    summarize(@meeting)
    assert_equal [ :meeting_analysis ], @calls, "The existing upstream meeting stage still runs; the topic stage must reuse"
    assert_equal original, @meeting.topic_summaries.sole.attributes
  end

  test "new meetings and added background retain valid history beyond the recent raw context cap" do
    summarize(@meeting)
    original = @meeting.topic_summaries.sole.attributes
    assert Topics::GenerationEvidence.summary_current?(@meeting.topic_summaries.sole)
    source = KnowledgeSource.create!(title: "Additional synthetic background", source_type: "note", origin: "manual", status: "approved", active: true)
    source.topics << @topic
    source.knowledge_chunks.create!(content: "Additional background, not a withdrawal", embedding: [ 0.3, 0.4 ])
    newest = nil
    4.times do |index|
      newest, = add_meeting("later-#{index}", "Distinct later synthetic decision #{index}", @meeting.starts_at + (index + 1).hours)
      summarize(newest)
    end
    briefing(newest)
    assert_equal @claims.values.sort, @briefing_inputs.last[:prior_meeting_analyses].map { |data| data["headline"] }.sort
    assert_equal 3, @briefing_inputs.last[:recent_raw_context].size
    assert_equal original, @meeting.topic_summaries.sole.attributes
  end

  test "topic merge preserves supported prior analysis when the canonical topic id changes" do
    summarize(@meeting)
    original = @meeting.topic_summaries.sole.generation_data.deep_dup
    target = Topic.create!(name: "Synthetic merged civic improvements", status: "approved")
    Topics::MergeService.new(source_topic: @topic, target_topic: target).call
    @topic = target
    briefing
    assert_equal [ @claims.fetch(@meeting.id) ], @briefing_inputs.last[:prior_meeting_analyses].map { |data| data["headline"] }
    assert_equal original, @meeting.topic_summaries.sole.generation_data
  end

  test "changed prompt settings invalidate reuse and an in flight prompt revision prevents publication" do
    template = PromptTemplate.create!(key: "analyze_topic_briefing", name: "Synthetic briefing", instructions: "Synthetic first contract", model_tier: "default")
    summarize(@meeting)
    briefing
    original = @topic.reload.topic_briefing.attributes
    template.update!(instructions: "Synthetic revised contract")
    @hooks[:briefing_analysis] = -> { template.update!(model_tier: "lightweight") }
    @calls.clear
    briefing
    assert_includes @calls, :briefing_analysis
    refute_includes @calls, :briefing_render
    assert_equal original, @topic.reload.topic_briefing.attributes
    @hooks.clear
    briefing
    refute_equal original.fetch("generation_data")["evidence_manifest"], @topic.reload.topic_briefing.generation_data["evidence_manifest"]
  end

  test "changed source is omitted from future briefing input while unrelated analysis and retained history survive" do
    other, = add_meeting("library", "Distinct retained synthetic library decision", 1.day.ago)
    summarize(@meeting)
    summarize(other)
    briefing(other)
    assert_equal @claims.values.sort, @briefing_inputs.last[:prior_meeting_analyses].map { |data| data["headline"] }.sort
    assert_includes @briefing_inputs.last[:recent_item_details].map { |entry| entry[:summary] }, @claims.fetch(@meeting.id)
    old_summary = @meeting.topic_summaries.sole.attributes
    old_meeting_summary = @meeting.meeting_summaries.sole.attributes

    revise(@document, "Corrected synthetic garden evidence")
    briefing(other)
    input = @briefing_inputs.last
    assert_equal [ @claims.fetch(other.id) ], input[:prior_meeting_analyses].map { |data| data["headline"] }
    assert_equal [ @claims.fetch(other.id) ], input[:recent_item_details].map { |entry| entry[:summary] }
    refute_includes input.to_json, @claims.fetch(@meeting.id)
    assert_equal old_summary, @meeting.topic_summaries.sole.attributes
    assert_equal old_meeting_summary, @meeting.meeting_summaries.sole.attributes
  end

  test "source change during briefing analysis prevents rendering publication and impact side effects" do
    summarize(@meeting)
    briefing
    original = @topic.reload.topic_briefing.attributes
    score = @topic.resident_impact_score
    @agenda.update!(summary: "A newly recorded agenda detail")
    @calls.clear
    @hooks[:briefing_analysis] = -> { revise(@document, "Replacement during analysis") }

    assert_no_enqueued_jobs only: GeneratedImages::RefreshHomepageTopicsJob do
      GeneratedImages::Config.stub(:enabled?, true) { briefing }
    end
    assert_includes @calls, :briefing_analysis
    refute_includes @calls, :briefing_render
    assert_equal original, @topic.reload.topic_briefing.attributes
    assert_equal score, @topic.resident_impact_score
  end

  test "removed source is not substituted and its prior headline leaves new description input" do
    summarize(@meeting)
    original = @meeting.topic_summaries.sole.attributes
    captured = []
    @ai.define_singleton_method(:generate_topic_description) do |context, **|
      captured << context.deep_dup
      "Synthetic description"
    end
    providers { Topics::GenerateDescriptionJob.perform_now(@topic.id) }
    assert_equal [ @claims.fetch(@meeting.id) ], captured.last[:headlines]
    retained = @document.source_versions.sole
    url = @document.source_url
    @document.destroy!
    replacement = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: url)
    revise(replacement, "A different document at the same URL")
    @topic.update!(description_generated_at: 91.days.ago)
    providers { Topics::GenerateDescriptionJob.perform_now(@topic.id) }
    assert_empty captured.last[:headlines]
    briefing
    assert_empty @briefing_inputs.last[:prior_meeting_analyses]
    refute_includes @briefing_inputs.last.to_json, @claims.fetch(@meeting.id)
    assert_equal original, @meeting.topic_summaries.sole.attributes
    assert_nil retained.reload.meeting_document_id
    assert retained.file.attached?
  end

  test "source change during rendering leaves the previous briefing and timestamp untouched" do
    summarize(@meeting)
    briefing
    original = @topic.reload.topic_briefing.attributes
    @agenda.update!(summary: "Another newly recorded agenda detail")
    @hooks[:briefing_render] = -> { revise(@document, "Replacement during rendering") }
    briefing
    assert_equal original, @topic.reload.topic_briefing.attributes
  end

  test "delayed briefing cannot overwrite a newer completed result for the same inputs" do
    summarize(@meeting)
    briefing
    @agenda.update!(summary: "New information shared by overlapping workers")
    newer = nil
    @hooks[:briefing_render] = -> {
      @hooks.delete(:briefing_render)
      Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      newer = @topic.reload.topic_briefing.attributes
    }
    briefing
    assert_equal "Synthetic briefing 3", newer.fetch("headline")
    assert_equal newer, @topic.reload.topic_briefing.attributes
  end

  test "delayed topic summary cannot overwrite a newer completed result" do
    summarize(@meeting)
    @agenda.update!(summary: "New information shared by overlapping workers")
    newer = nil
    @hooks[:summary_render] = -> {
      @hooks.delete(:summary_render)
      @claims[@meeting.id] = "A newer completed synthetic interpretation"
      Topics::GenerateSummary.new(@topic, @meeting, ai_service: @ai, retrieval_service: @retrieval).call
      newer = @meeting.topic_summaries.sole.attributes
    }
    summarize(@meeting)
    assert_equal "A newer completed synthetic interpretation", newer.fetch("generation_data").fetch("headline")
    assert_equal newer, @meeting.topic_summaries.sole.attributes
  end

  test "reviewed decision withdrawal invalidates prior analysis while preserving its neutral evidence receipt" do
    publish_decision
    summarize(@meeting)
    briefing
    old = @meeting.topic_summaries.sole.attributes
    event = @topic.topic_status_events.where(evidence_type: "motion_outcome").sole
    reference = old.fetch("generation_data").fetch("evidence_manifest").fetch("motion_evidence")
      .find { |entry| entry["event_id"] == event.id }.fetch("reference")
    assert_equal event.council_decision.public_id, reference.fetch("decision_public_id")
    assert_equal event.decision_observation.minutes_extraction.source_key, reference.fetch("source_key")
    assert_equal [ @claims.fetch(@meeting.id) ], @briefing_inputs.last[:prior_meeting_analyses].map { |data| data["headline"] }
    actor = User.create!(email_address: "private-generation-reviewer@example.test", admin: true, status: "active")
    reason = "Private synthetic generation identity withdrawal"
    CouncilDecisions::ResolveIdentity.call(observation: event.decision_observation, action: "unassign", actor: actor,
      reason: reason, expected_correction_id: nil, request_id: SecureRandom.uuid)
    briefing
    assert_empty @briefing_inputs.last[:prior_meeting_analyses]
    current = @briefing_inputs.last[:continuity_context][:status_events].find { |entry| entry[:event_id] == event.id }
    assert_nil current.dig(:motion_reference, :decision_public_id)
    assert_equal old, @meeting.topic_summaries.sole.attributes
    refute_includes @topic.reload.topic_briefing.generation_data.to_json, actor.email_address
    refute_includes @topic.topic_briefing.generation_data.to_json, reason
  end

  test "operator reanalysis also refuses a topic result whose source changes during rendering" do
    summarize(@meeting)
    original = @meeting.topic_summaries.sole.attributes
    @agenda.update!(summary: "An operator requested a revised analysis")
    @hooks[:summary_render] = -> { revise(@document, "Replacement during operator generation") }
    providers { Topics::MeetingReanalysisService.new(@meeting.id).call }
    assert_includes @calls, :summary_render
    assert_equal [ @topic.id ], @agenda.reload.topics.pluck(:id)
    assert_equal original, @meeting.topic_summaries.sole.attributes
    assert_empty @briefing_inputs.last[:prior_meeting_analyses]
  end

  test "operator reanalysis establishes continuity before generating a new topic record" do
    providers { Topics::MeetingReanalysisService.new(@meeting.id).call }
    summary = @meeting.topic_summaries.sole
    assert Topics::GenerationEvidence.summary_current?(summary)
    assert_equal 1, @calls.count(:summary_analysis)
    assert_equal [ @claims.fetch(@meeting.id) ], @briefing_inputs.last[:prior_meeting_analyses].map { |data| data["headline"] }
  end

  test "full meeting workflow refuses a stale topic analysis before its render or followup" do
    @hooks[:summary_analysis] = -> { revise(@document, "Replacement during topic analysis") }
    assert_no_enqueued_jobs only: Topics::GenerateTopicBriefingJob do
      summarize(@meeting)
    end
    assert_includes @calls, :summary_analysis
    refute_includes @calls, :summary_render
    assert_empty @meeting.topic_summaries
    assert_equal 1, @meeting.meeting_summaries.count, "Retain the prior source analysis for inspection"
  end

  test "withdrawn knowledge prevents stale output without storing private context in dependency receipts" do
    source = KnowledgeSource.create!(title: "Private synthetic background", source_type: "note", origin: "manual", status: "approved", active: true)
    source.topics << @topic
    source.knowledge_chunks.create!(content: "Private source note not for public metadata", embedding: [ 0.1, 0.2 ])
    summarize(@meeting)
    briefing
    original = @topic.reload.topic_briefing.attributes
    manifest = @topic.topic_briefing.generation_data["evidence_manifest"]
    assert manifest, "Published output needs a dependency receipt"
    refute_includes manifest.to_json, "Private source note"
    refute_includes manifest.to_json, source.title
    @agenda.update!(summary: "New evidence requires another briefing")
    @hooks[:briefing_analysis] = -> { source.update!(status: "blocked") }
    @calls.clear
    briefing
    refute_includes @calls, :briefing_render
    assert_equal original, @topic.reload.topic_briefing.attributes
    @hooks.clear
    briefing
    assert_empty @briefing_inputs.last[:prior_meeting_analyses]
  end

  private

  def publish_decision
    excerpt = @claims.fetch(@meeting.id)
    @ai.define_singleton_method(:extract_votes) do |*args, **|
      { motions: [ { description: excerpt, source_excerpt: excerpt, agenda_item_ref: "5: Synthetic garden improvements",
        outcome: "passed", votes: [ { member: "Alex Example", value: "yes" } ] } ] }.to_json
    end
    @ai.define_singleton_method(:extract_committee_members) do |*args, **|
      { voting_members_present: [ "Alex Example" ], voting_members_absent: [], non_voting_staff: [], guests: [] }.to_json
    end
    providers do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id)
    end
  end

  def add_meeting(key, claim, starts_at)
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: starts_at, detail_page_url: "https://example.test/generation-#{key}")
    document = meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/generation-#{key}.pdf")
    agenda = meeting.agenda_items.create!(number: "5", title: "Synthetic #{key} improvements", order_index: 1)
    agenda.topics << @topic
    @claims[meeting.id] = claim
    revise(document, claim)
    [ meeting, document, agenda ]
  end

  def revise(document, text)
    URI.stub(:open, ->(*) { StringIO.new(text) }) { Documents::DownloadJob.perform_now(document.id) }
    Documents::PublishText.new(document.reload).call(raw_pages: [ text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
  end

  def build_providers
    calls, hooks, claims = @calls, @hooks, @claims
    summaries, briefings = @summary_inputs, @briefing_inputs
    @ai = Object.new
    agenda, topic = @agenda, @topic
    @ai.define_singleton_method(:extract_topics) do |*args, **|
      { items: [ { id: agenda.id, category: "Infrastructure", tags: [ topic.name ], topic_worthy: true, confidence: 0.9 } ] }.to_json
    end
    @ai.define_singleton_method(:prepare_kb_context) { |*| "" }
    @ai.define_singleton_method(:analyze_meeting_content) do |*, source:, **|
      calls << :meeting_analysis
      item = source.agenda_items.sole
      { headline: claims.fetch(source.id), item_details: [ { agenda_item_id: item.id, title: item.title, summary: claims.fetch(source.id),
        citations: [ { source_id: "doc-#{source.meeting_documents.sole.id}", location: { kind: "whole_source" } } ] } ] }.to_json
    end
    @ai.define_singleton_method(:analyze_topic_summary) do |context, **|
      calls << :summary_analysis
      summaries << context.deep_dup
      hooks[:summary_analysis]&.call
      { headline: claims.fetch(context[:meeting_metadata][:id]), factual_record: [], resident_impact: { score: 2 } }.to_json
    end
    @ai.define_singleton_method(:render_topic_summary) do |*args, **|
      calls << :summary_render
      hooks[:summary_render]&.call
      "Synthetic per-meeting record"
    end
    @ai.define_singleton_method(:analyze_topic_briefing) do |context, **|
      calls << :briefing_analysis
      briefings << context.deep_dup
      hooks[:briefing_analysis]&.call
      { headline: "Synthetic briefing #{briefings.size}", factual_record: [], resident_impact: { score: 4 } }.to_json
    end
    @ai.define_singleton_method(:render_topic_briefing) do |*args, **|
      calls << :briefing_render
      hooks[:briefing_render]&.call
      { "editorial_content" => "Synthetic story", "record_content" => "Synthetic record" }
    end
    @retrieval = Object.new
    @retrieval.define_singleton_method(:retrieve_context) { |*args, **| [] }
    @retrieval.define_singleton_method(:format_context) { |*args| "" }
    @retrieval.define_singleton_method(:retrieve_topic_context) { |**| calls << :topic_retrieval; [] }
    @retrieval.define_singleton_method(:format_topic_context) { |*args| [] }
  end

  def providers(&block)
    Ai::OpenAiService.stub(:new, @ai) { RetrievalService.stub(:new, @retrieval, &block) }
  end

  def summarize(meeting)
    providers { SummarizeMeetingJob.perform_now(meeting.id, enqueue_followups: false) }
  end

  def briefing(meeting = @meeting)
    providers { Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: meeting.id) }
  end
end
