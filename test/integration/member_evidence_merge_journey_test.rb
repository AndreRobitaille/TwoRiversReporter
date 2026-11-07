require "test_helper"
require "minitest/mock"
require "open-uri"

class MemberEvidenceMergeJourneyTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "synthetic-merge-reviewer@example.test", admin: true, status: "active")
    sign_in_as_admin(@admin)
    @source = Member.create!(name: "A. Example")
    @target = Member.create!(name: "Alex Example")
    @other = Member.create!(name: "Blair Sample")
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/merge-evidence")
    @document = @meeting.meeting_documents.create!(source_url: "https://example.test/merge-evidence.pdf", document_type: "minutes_pdf")
    @agenda = @meeting.agenda_items.create!(number: "5", title: "Synthetic garden funding", order_index: 1)
    @topic = Topic.create!(name: @agenda.title, status: "approved")
    @agenda.topics << @topic
    @excerpt = "Motion to fund the synthetic garden passed. A. Example and Alex Example voted yes; Blair Sample voted no."
    URI.stub(:open, ->(*) { StringIO.new("synthetic retained artifact") }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: [ @excerpt ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    run_stage(:extract_votes, motions: [ { description: "Fund the synthetic garden", agenda_item_ref: "5: Synthetic garden funding", outcome: "passed",
      source_excerpt: @excerpt, votes: [ { member: @source.name, value: "yes" }, { member: @target.name, value: "yes" }, { member: @other.name, value: "no" } ] } ])
    run_stage(:extract_committee_members, voting_members_present: [ @source.name, @target.name, @other.name ], voting_members_absent: [], non_voting_staff: [], guests: [])
    without_ai { Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id) }
  end

  test "compatible member merge survives cached reprocessing without changing retained decision evidence" do
    motion = @meeting.motions.sole
    observation = motion.decision_observation
    review = CouncilDecisions::ResolveIdentity.call(observation: observation, action: "assign", decision: motion.council_decision,
      basis_observation: observation, actor: @admin, reason: "Synthetic retained identity check", expected_correction_id: nil, request_id: SecureRandom.uuid)
    retained = observation.attributes
    event = @topic.topic_status_events.where(evidence_type: "motion_outcome").sole
    stage_ids = @meeting.minutes_extractions.order(:id).pluck(:id)
    original_motion_id = motion.id
    assert_equal [ [ @source.id, "yes" ], [ @target.id, "yes" ], [ @other.id, "no" ] ].sort, motion.votes.pluck(:member_id, :value).sort
    assert_member_vote(@source, "Yes")
    assert_member_vote(@target, "Yes")

    without_ai { post merge_admin_member_path(@source), params: { target_member_id: @target.id } }
    assert_redirected_to admin_member_path(@target)
    refute Member.exists?(@source.id)
    assert_equal @target.id, Member.resolve(@source.name).id
    assert_equal 2, @meeting.meeting_attendances.count
    assert_equal [ [ @target.id, "yes" ], [ @other.id, "no" ] ].sort, motion.votes.pluck(:member_id, :value).sort

    # Force deterministic display reconstruction from the same completed stages.
    @meeting.update!(starts_at: @meeting.starts_at - 1.hour)
    without_ai do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      Topics::UpdateContinuityJob.perform_now(meeting_id: @meeting.id)
    end
    current = @meeting.motions.sole
    refute_equal original_motion_id, current.id
    assert_equal stage_ids, @meeting.minutes_extractions.order(:id).pluck(:id)
    assert_equal retained, observation.reload.attributes
    assert_equal observation.id, current.decision_observation_id
    assert_equal review.id, observation.identity_assignment.reload.correction_id
    assert_equal event.id, @topic.topic_status_events.where(evidence_type: "motion_outcome").sole.id
    assert_equal observation.council_decision.public_id, event.reload.council_decision.public_id
    assert_equal [ [ @target.id, "yes" ], [ @other.id, "no" ] ].sort, current.votes.pluck(:member_id, :value).sort
    assert_equal [ @target.id, @other.id ].sort, @meeting.meeting_attendances.pluck(:member_id).sort
    refute Member.exists?(@source.id)
    assert_equal [ @source.name, @target.name, @other.name ], observation.data.fetch("votes").map { |vote| vote.fetch("member") }
    assert_member_vote(@target, "Yes")
    assert_member_vote(@other, "No")
  end

  test "conflicting votes refuse the HTTP merge and preserve both later member records" do
    @source.votes.sole.update!(value: "no")
    assert_member_vote(@source, "No")
    assert_member_vote(@target, "Yes")
    before = persisted_records
    without_ai { post merge_admin_member_path(@source), params: { target_member_id: @target.id } }
    assert_redirected_to admin_member_path(@source)
    assert_match(/Conflicting votes/, flash[:alert])
    assert_equal before, persisted_records
    follow_redirect!
    assert_response :success
    assert_includes response.body, "Conflicting votes"
    assert_member_vote(@source, "No")
    assert_member_vote(@target, "Yes")
  end

  test "attendance conflict rolls back earlier vote deduplication and preserves the source" do
    @source.meeting_attendances.sole.update!(status: "absent")
    before = persisted_records
    without_ai { post merge_admin_member_path(@source), params: { target_member_id: @target.id } }
    assert_redirected_to admin_member_path(@source)
    assert_match(/Conflicting attendance/, flash[:alert])
    assert_equal before, persisted_records
    assert_equal "absent", @source.meeting_attendances.sole.status
    assert_equal "present", @target.meeting_attendances.sole.status
    assert_member_vote(@source, "Yes")
    assert_member_vote(@target, "Yes")
  end

  private

  def persisted_records
    [ Member, MemberAlias, Vote, MeetingAttendance, CouncilDecisionObservation, CouncilDecisionAssignment, TopicStatusEvent ]
      .to_h { |model| [ model.name, model.order(:id).map(&:attributes) ] }
  end

  def run_stage(method, data)
    service = Object.new
    service.define_singleton_method(method) { |*args, **kwargs| data.to_json }
    job = method == :extract_votes ? ExtractVotesJob : ExtractCommitteeMembersJob
    Ai::OpenAiService.stub(:new, service) { job.perform_now(@meeting.id) }
  end

  def without_ai(&block)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Merge, cached reconstruction and reads must not dispatch AI" }, &block)
  end

  def assert_member_vote(member, value)
    without_ai { get member_path(member) }
    assert_response :success
    assert_select ".member-vote-row", count: 1
    assert_select ".member-vote-motion", text: /Synthetic garden funding/
    assert_select ".vote-value", text: value, count: 1
  end
end
