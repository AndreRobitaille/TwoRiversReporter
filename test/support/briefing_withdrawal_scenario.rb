require "minitest/mock"
require "open-uri"

# Synthetic records, deterministic provider transport, real evidence publication
# and generation. These claims are not assertions about an actual official.
module BriefingWithdrawalScenario
  CLAIM = "Syntheticcedaridentityreport".freeze
  STORY = "Synthetic cedar interpretation awaiting a corrected identity".freeze

  def build_withdrawal_scenario
    @committee = Committee.create!(name: "Synthetic Council", slug: "synthetic-council", status: "active")
    @meeting = Meeting.create!(body_name: @committee.name, committee: @committee, starts_at: 1.day.ago,
      detail_page_url: "https://example.test/withdrawal-meeting")
    @topic = Topic.create!(name: "Synthetic cedar improvements", status: "approved", resident_impact_score: 5)
    @other = Topic.create!(name: "Synthetic maple improvements", status: "approved", resident_impact_score: 4)
    @agenda = @meeting.agenda_items.create!(number: "5", title: @topic.name, order_index: 1)
    @agenda.topics << @topic
    @meeting.agenda_items.create!(number: "6", title: @other.name, order_index: 2).topics << @other
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/withdrawal-minutes.pdf")
    text = "Motion to approve the synthetic cedar improvements passed. Alex Example voted yes."
    URI.stub(:open, ->(*) { StringIO.new(text) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: [ text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    @provider = Object.new
    agenda_reference = "#{@agenda.number}: #{@agenda.title}"
    @provider.define_singleton_method(:extract_votes) do |*, **|
      { motions: [ { description: "Approve synthetic cedar improvements", source_excerpt: text,
        agenda_item_ref: agenda_reference, outcome: "passed", votes: [ { member: "Alex Example", value: "yes" } ] } ] }.to_json
    end
    @provider.define_singleton_method(:extract_committee_members) do |*, **|
      { voting_members_present: [ "Alex Example" ], voting_members_absent: [], non_voting_staff: [], guests: [] }.to_json
    end
    @provider.define_singleton_method(:analyze_topic_briefing) do |context, source:, **|
      affected = source.name.include?("cedar")
      { headline: affected ? CLAIM : "Synthetic maple report remains supported",
        editorial_analysis: { current_state: affected ? STORY : "Synthetic maple story", what_to_watch: "Synthetic next steps" },
        factual_record: [ { event: affected ? STORY : "Synthetic maple event", date: context[:recent_raw_context].first&.dig(:meeting_date), meeting: "Synthetic Council" } ] }.to_json
    end
    @provider.define_singleton_method(:render_topic_briefing) do |json, **|
      { "editorial_content" => JSON.parse(json).dig("editorial_analysis", "current_state"), "record_content" => "Synthetic rendered record" }
    end
    @retrieval = Object.new
    @retrieval.define_singleton_method(:retrieve_topic_context) { |**| [] }
    @retrieval.define_singleton_method(:format_topic_context) { |*| [] }
    withdrawal_providers do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id)
      @topic.reload.update!(lifecycle_status: "active")
      [ @topic, @other ].each { |topic| Topics::GenerateTopicBriefingJob.perform_now(topic_id: topic.id, meeting_id: @meeting.id) }
    end
    @briefing = @topic.reload.topic_briefing
    @other_briefing = @other.reload.topic_briefing
    @event = @topic.topic_status_events.where(evidence_type: "motion_outcome").sole
    assert_not_nil @event.council_decision
    assert_equal @event.decision_observation_id, @briefing.generation_data.dig("evidence_manifest", "motion_evidence")
      .find { |entry| entry["event_id"] == @event.id }.dig("reference", "observation_id")
    @actor = User.create!(email_address: "private-withdrawal-reviewer@example.test", status: "active", admin: true)
  end

  def withdraw_decision
    @correction = CouncilDecisions::ResolveIdentity.call(observation: @event.decision_observation, action: "unassign",
      actor: @actor, reason: "Private synthetic identity correction", expected_correction_id: nil, request_id: SecureRandom.uuid)
    assert_not_nil @briefing.reload.evidence_withdrawn_at
    assert_equal @correction.id, @briefing.withdrawal_correction_id
  end

  def withdrawal_providers(&block)
    Ai::OpenAiService.stub(:new, @provider) { RetrievalService.stub(:new, @retrieval, &block) }
  end

  def without_paid_providers(&block)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Withdrawal and resident reads must not request AI" }) do
      RetrievalService.stub(:new, ->(*) { flunk "Withdrawal and resident reads must not request embeddings" }, &block)
    end
  end

  def clean_withdrawal_scenario
    AuditEvent.where(subject_type: "TopicBriefing", subject_id: TopicBriefing.where(topic_id: [ @topic&.id, @other&.id, @merge_target&.id ]).select(:id)).delete_all
    AuditEvent.where(actor_id: @actor&.id).delete_all
    Topic.where(id: [ @topic&.id, @other&.id, @merge_target&.id ]).destroy_all
    Redirect.where(source_path: "/topics/#{@topic&.id}").delete_all
    if @meeting&.persisted?
      stage_ids = @meeting.minutes_extractions.pluck(:id)
      publication_ids = @meeting.minutes_publications.pluck(:id)
      decision_ids = @meeting.council_decisions.pluck(:id)
      observation_ids = CouncilDecisionObservation.where(minutes_extraction_id: stage_ids).pluck(:id)
      versions = MeetingDocumentVersion.where(original_meeting_id: @meeting.id).to_a
      text_versions = MeetingDocumentTextVersion.where(meeting_document_version_id: versions.map(&:id)).to_a
      TranscriptImport.where(meeting_id: @meeting.id).destroy_all
      @meeting.destroy!
      MinutesPublication.where(id: publication_ids).destroy_all
      CouncilDecisionAssignment.where(minutes_extraction_id: stage_ids).delete_all
      CouncilDecisionCorrection.where(observation_id: observation_ids).delete_all
      CouncilDecisionObservation.where(id: observation_ids).destroy_all
      CouncilDecision.where(id: decision_ids).destroy_all
      MinutesExtraction.where(id: stage_ids).destroy_all
      text_versions.each(&:destroy!)
      versions.each(&:destroy!)
    end
    @committee&.destroy!
    Member.where(name: "Alex Example").destroy_all
    User.where(id: @actor&.id).delete_all
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end
end
