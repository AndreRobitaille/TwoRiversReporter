require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesTopicEvidenceTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/topic-evidence")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/topic-evidence.pdf")
    @agenda = @meeting.agenda_items.create!(number: "5", title: "Synthetic improvements", order_index: 1)
    @topic = Topic.create!(name: "Synthetic improvements", status: "approved")
    @agenda.topics << @topic
    @excerpts = [ "Motion to fund the synthetic garden passed; Alex Example voted yes.",
      "Motion to adopt the synthetic garden rules passed; Alex Example voted yes." ]
    revision("first", @excerpts)
  end

  test "distinct decisions retain separate topic events when their date and outcome agree" do
    publish
    events = motion_events.to_a
    assert_equal 2, events.size, "Each decision needs its own retained evidence event"
    assert_equal @meeting.motions.pluck(:decision_observation_id).sort, events.map(&:decision_observation_id).sort
    assert_equal @excerpts.sort, events.map { |event| event.decision_observation.data.fetch("source_excerpt") }.sort
    assert_equal 2, events.map { |event| event.council_decision.public_id }.uniq.size
  end

  test "reprojection preserves event identity and retained evidence after motion rows are replaced" do
    publish(excerpts: [ @excerpts.first ])
    event = motion_events.sole
    assert event.try(:decision_observation), "The event must retain an observation independently of its display motion"
    original_motion_id = @meeting.motions.sole.id
    original_observation_id = event.decision_observation_id
    original_decision_id = event.council_decision.public_id
    @meeting.update!(starts_at: @meeting.starts_at - 1.day)
    assert_empty motion_events.with_current_evidence
    without_ai do
      ExtractVotesJob.perform_now(@meeting.id)
      Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id)
    end
    refute Motion.exists?(original_motion_id)
    current = motion_events.sole
    assert_equal event.id, current.id
    assert_equal original_observation_id, current.decision_observation_id
    assert_equal original_decision_id, current.council_decision.public_id
    assert_equal @meeting.starts_at, current.occurred_at
    assert_equal [ current.id ], motion_events.with_current_evidence.pluck(:id)
    assert_equal @excerpts.first, current.decision_observation.data.fetch("source_excerpt")
  end

  test "source revision retains historical events but only current outcomes reach summary providers" do
    publish
    old_events = motion_events.to_a
    old_events.each { |event| event.update!(notes: "Superseded synthetic outcome #{event.id}") }
    assert_equal old_events.map(&:id), motion_events.with_current_evidence.pluck(:id)
    assert_equal old_events.map(&:notes).sort, summary_motion_notes.sort
    assert_equal old_events.map(&:notes).sort, briefing_motion_notes.sort

    changed = "The synthetic garden funding motion failed; Alex Example voted no."
    revision("withdrawn", [ changed, @excerpts.last ])
    publish(excerpts: [ changed, @excerpts.last ], outcome: [ "failed", "passed" ])
    assert_equal 2, @meeting.motions.count
    assert_equal 1, motion_events.with_current_evidence.count
    current = motion_events.with_current_evidence.sole
    current.update!(notes: "Current synthetic rules outcome")
    assert_equal 3, motion_events.count
    assert_equal old_events.map(&:id), motion_events.where(id: old_events).pluck(:id)
    assert_equal @excerpts.sort, old_events.map { |event| event.reload.decision_observation.data["source_excerpt"] }.sort
    assert_equal [ current.notes ], summary_motion_notes
    assert_equal [ current.notes ], briefing_motion_notes
    assert_equal "Synthetic test record", @topic.reload.topic_briefing.record_content
    without_ai do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id)
    end
    assert_equal [ current.id ], motion_events.with_current_evidence.pluck(:id)
    assert_equal 3, motion_events.count
  end

  test "identity corrections change effective decision lookup without erasing event source evidence" do
    publish
    event = motion_events.find_by!(decision_observation_id: @meeting.motions.order(:id).first.decision_observation_id)
    decision = event.council_decision
    actor = User.create!(email_address: "synthetic-reviewer@example.test", admin: true, status: "active")
    review = CouncilDecisions::ResolveIdentity.call(observation: event.decision_observation, action: "unassign", actor: actor,
      reason: "Synthetic identity correspondence withdrawal", expected_correction_id: nil, request_id: SecureRandom.uuid)
    assert_nil TopicStatusEvent.find(event.id).council_decision
    assert_nil decision.reload.current_observation
    assert_equal review.id, event.reload.identity_assignment.correction_id
    assert_equal decision.id, event.decision_observation.council_decision_id
    assert_equal @excerpts.first, event.decision_observation.data["source_excerpt"]
    assert_equal "extracted", event.decision_observation.evidence_status
    assert_equal 2, motion_events.with_current_evidence.count
  end

  test "topic merge retains both histories but presents each supported decision once" do
    publish
    source = Topic.create!(name: "Synthetic garden alias topic", status: "approved")
    @agenda.topics << source
    without_ai { Topics::UpdateContinuityJob.perform_now(topic_id: source.id) }
    original_ids = TopicStatusEvent.where(topic: [ @topic, source ], evidence_type: "motion_outcome").pluck(:id)
    assert_equal 4, original_ids.size
    without_ai do
      Topics::MergeService.new(source_topic: source, target_topic: @topic).call
      Topics::UpdateContinuityJob.perform_now(topic_id: @topic.id)
    end
    assert_equal original_ids.sort, motion_events.pluck(:id).sort
    assert_equal 2, motion_events.with_current_evidence.count
    assert_equal @excerpts.sort, motion_events.with_current_evidence.map { |event| event.decision_observation.data["source_excerpt"] }.sort
    assert_equal [ @topic.id ], TopicStatusEvent.where(id: original_ids).distinct.pluck(:topic_id)
  end

  test "only an exact live legacy reference is adopted and orphaned evidence stays unresolved" do
    publish
    motion_events.delete_all
    motion = @meeting.motions.order(:id).first
    legacy = @topic.topic_status_events.create!(lifecycle_status: "resolved", evidence_type: "motion_outcome",
      occurred_at: @meeting.starts_at, source_ref: { motion_id: motion.id, outcome: motion.outcome }, notes: "Live legacy outcome")
    orphan = @topic.topic_status_events.create!(lifecycle_status: "resolved", evidence_type: "motion_outcome",
      occurred_at: @meeting.starts_at, source_ref: { motion_id: "unavailable-synthetic-id", outcome: "passed" }, notes: "Unsupported synthetic outcome")
    assert_equal [ legacy.id ], motion_events.with_current_evidence.pluck(:id)
    without_ai { Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id) }
    assert_equal motion.decision_observation_id, legacy.reload.decision_observation_id
    assert_nil orphan.reload.decision_observation_id
    assert_equal 3, motion_events.count
    assert_equal 2, motion_events.with_current_evidence.count
    refute_includes summary_motion_notes, orphan.notes
    refute_includes briefing_motion_notes, orphan.notes
  end

  test "unlinked evidence leaves current context and removed sources retain their exact prior artifact" do
    publish
    events = motion_events.to_a
    assert_equal 2, motion_events.with_current_evidence.count
    @agenda.topics.delete(@topic)
    assert_empty motion_events.with_current_evidence
    assert_empty summary_motion_notes
    @agenda.topics << @topic
    assert_equal 2, motion_events.with_current_evidence.count
    @document.destroy!
    assert_equal @excerpts.sort, events.map { |event| event.reload.decision_observation.data["source_excerpt"] }.sort
    assert_equal 2, motion_events.count
    events.each do |event|
      artifact = event.reload.decision_observation.minutes_extraction.meeting_document_text_version.meeting_document_version
      assert_nil artifact.meeting_document
      assert artifact.file.attached?
      assert_equal "https://example.test/topic-evidence.pdf", artifact.source_url
    end
  end

  test "retained event evidence cannot be replaced and schema rollback cannot discard its link" do
    publish
    first, second = motion_events.to_a
    original_excerpt = first.decision_observation.data["source_excerpt"]
    assert_raises(ActiveRecord::RecordInvalid) { first.update!(decision_observation: second.decision_observation) }
    first.reload
    assert_raises(ActiveRecord::RecordInvalid) { first.update!(source_ref: { "outcome" => "failed" }) }
    require Rails.root.join("db/migrate/20261108000000_pin_topic_motion_evidence")
    assert_raises(ActiveRecord::IrreversibleMigration) { PinTopicMotionEvidence.new.down }
    assert_equal original_excerpt, first.reload.decision_observation.data["source_excerpt"]
  end

  test "summary boundaries retain distinct evidence references without private review metadata" do
    publish
    retained = motion_events.to_a
    reviewed = retained.first.decision_observation
    actor = User.create!(email_address: "private-source-reviewer@example.test", admin: true, status: "active")
    reason = "Private synthetic identity review notes"
    CouncilDecisions::ResolveIdentity.call(observation: reviewed, action: "assign", decision: reviewed.council_decision,
      basis_observation: reviewed, actor: actor, reason: reason, expected_correction_id: nil, request_id: SecureRandom.uuid)
    [ summary_motion_events, briefing_motion_events ].each do |events|
      assert_equal retained.map(&:id).sort, events.map { |event| event[:event_id] }.compact.sort
      references = events.map { |event| event.fetch(:motion_reference) }
      assert_equal retained.map(&:decision_observation_id).sort, references.map { |ref| ref.fetch(:observation_id) }.sort
      assert_equal retained.map { |event| event.council_decision.public_id }.sort, references.map { |ref| ref.fetch(:decision_public_id) }.sort
      assert_equal [ reviewed.minutes_extraction.source_key ], references.map { |ref| ref.fetch(:source_key) }.uniq
      assert_equal [ reviewed.minutes_extraction.meeting_document_text_version_id ], references.map { |ref| ref.fetch(:text_version_id) }.uniq
      assert_equal [ "retained_artifact" ], references.map { |ref| ref.fetch(:source_provenance) }.uniq
      assert_equal [ "extracted" ], references.map { |ref| ref.fetch(:evidence_status) }.uniq
      refute_includes events.to_json, actor.email_address
      refute_includes events.to_json, reason
    end
  end

  private

  def motion_events
    @topic.topic_status_events.where(evidence_type: "motion_outcome").order(:id)
  end

  def summary_motion_notes
    summary_motion_events.map { |event| event[:notes] }
  end

  def summary_motion_events
    Topics::SummaryContextBuilder.new(@topic, @meeting).build_context_json[:continuity_context][:recent_status_events]
      .select { |event| event[:evidence] == "motion_outcome" }
  end

  def briefing_motion_notes
    briefing_motion_events.map { |event| event[:notes] }
  end

  def briefing_motion_events
    captured = nil
    calls = 0
    service = Object.new
    service.define_singleton_method(:analyze_topic_briefing) do |context, **kwargs|
      captured = context
      calls += 1
      { headline: "Synthetic test briefing", factual_record: [] }.to_json
    end
    service.define_singleton_method(:render_topic_briefing) do |*args, **kwargs|
      calls += 1
      { "editorial_content" => "Synthetic test editorial", "record_content" => "Synthetic test record" }
    end
    retrieval = Object.new
    retrieval.define_singleton_method(:retrieve_topic_context) { |*args, **kwargs| [] }
    retrieval.define_singleton_method(:format_topic_context) { |*args| [] }
    Ai::OpenAiService.stub :new, service do
      RetrievalService.stub :new, retrieval do
        Topics::GenerateTopicBriefingJob.perform_now(topic_id: @topic.id, meeting_id: @meeting.id)
      end
    end
    assert_equal 2, calls
    captured[:continuity_context][:status_events].select { |event| event[:event_type] == "motion_outcome" }
  end

  def revision(bytes, pages)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: pages, page_count: pages.size, quality: "text", extractor_version: "synthetic_v1")
    @document.reload
  end

  def publish(excerpts: @excerpts, outcome: "passed")
    votes = { motions: excerpts.each_with_index.map do |excerpt, index|
      result = outcome.is_a?(Array) ? outcome[index] : outcome
      { description: excerpt, source_excerpt: excerpt, agenda_item_ref: "5: Synthetic improvements", outcome: result,
        votes: [ { member: "Alex Example", value: result == "failed" ? "no" : "yes" } ] }
    end }
    attendance = { voting_members_present: [ "Alex Example" ], voting_members_absent: [], non_voting_staff: [], guests: [] }
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| votes.to_json }
    service.define_singleton_method(:extract_committee_members) { |*args, **kwargs| attendance.to_json }
    Ai::OpenAiService.stub :new, service do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    @meeting.reload
    without_ai { Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id) }
  end

  def without_ai(&block)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Deterministic continuity and replay must not dispatch providers" }, &block)
  end
end
