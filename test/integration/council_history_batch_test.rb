require "test_helper"
require_relative "../support/council_spend_scenario"

class CouncilHistoryBatchTest < ActiveJob::TestCase
  include CouncilSpendScenario
  self.use_transactional_tests = false

  setup do
    travel_to Time.zone.local(2026, 11, 21, 12)
    setup_spend_scenario(source_url: "https://example.test/#{CouncilHistory::Batch::PILOT.fetch('2024-10-28')}")
    @meeting.update!(starts_at: Time.zone.local(2024, 10, 28, 18), body_name: "City Council Work Session")
    @meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: "Existing accepted recap")
  end

  teardown do
    CouncilHistoryRequest.where(meeting_id: @meeting.id).delete_all
    cleanup_spend_scenario
  end

  test "the scoped pilot publishes the roll call once while preserving the saved recap and ordinary queue" do
    listing = { "title" => @meeting.body_name, "starts_at" => @meeting.starts_at.iso8601, "url" => @meeting.detail_page_url,
      "documents" => { "minutes_pdf" => @document.source_url } }
    cancelled = listing.merge("title" => "City Council Meeting CANCELLED", "url" => "https://example.test/cancelled")
    even_older = listing.merge("starts_at" => Time.zone.local(2024, 9, 1, 18).iso8601, "url" => "https://example.test/other")
    batch = CouncilHistory::Batch.new([ listing, cancelled, even_older ], pilot: true)
    assert_no_enqueued_jobs(only: ->(job) { job.is_a?(ApplicationJob) }) do
      with_transport { batch.call(stages: [ "facts" ]) }
    end
    assert_equal 2, @calls.size
    assert_equal %w[attendance votes], CouncilHistoryRequest.where(meeting_id: @meeting.id, pilot: true).order(:stage).pluck(:stage)
    assert_equal 2, @meeting.reload.motions.sole.votes.count
    assert_equal "no", @meeting.motions.sole.votes.joins(:member).find_by!(members: { name: "Alex Budget" }).value
    assert_equal "Existing accepted recap", @meeting.meeting_summaries.sole.content
    assert_not Meeting.exists?(detail_page_url: even_older.fetch("url"))
    with_transport { batch.call }
    assert_equal 2, @calls.size
    assert_equal 2, CouncilHistoryRequest.where(meeting_id: @meeting.id).count
  end

  test "reviewing a supplemental agenda preserves published vote identities and prevents repeat paid calls" do
    listing = { "title" => @meeting.body_name, "starts_at" => @meeting.starts_at.iso8601, "url" => @meeting.detail_page_url,
      "documents" => { "minutes_pdf" => @document.source_url } }
    batch = CouncilHistory::Batch.new([ listing ])
    with_transport { batch.call(stages: [ "facts" ]) }
    publication = @meeting.reload.minutes_publication
    motion = @meeting.motions.sole
    original_votes = motion.votes.order(:id).pluck(:id, :member_id, :value, :evidence_basis)
    agenda = @meeting.meeting_documents.create!(document_type: "agenda_pdf", source_url: "https://example.test/recovered-agenda.pdf")
    URI.stub(:open, ->(*) { StringIO.new("original agenda PDF") }) { Documents::DownloadJob.perform_now(agenda.id) }
    item = @meeting.agenda_items.create!(number: "7.", title: "Harbor repair bid", kind: "item", order_index: 1)
    refute Minutes::Publish.current?(@meeting.reload)
    assert Minutes::Pipeline.needed?(@meeting, "votes")
    actor = User.create!(email_address: "review-agenda@example.test", admin: true, status: "active")
    2.times do
      CouncilHistory::ReviewedFacts.preserve_published_votes!(@meeting, actor: actor, agenda: agenda)
      assert Minutes::Publish.current?(@meeting.reload), "Review must preserve the accepted publication"
      with_transport { batch.call(stages: [ "facts" ]) }
    end
    assert Minutes::Publish.current?(@meeting.reload)
    assert_equal publication.id, @meeting.minutes_publication_id
    assert_equal original_votes, motion.reload.votes.order(:id).pluck(:id, :member_id, :value, :evidence_basis)
    assert_equal 2, @calls.size
    assert_equal 1, AuditEvent.where(action: "council_history.review_supplemental_agenda", subject: @meeting).count
    item.update!(title: "Different harbor bid")
    refute Minutes::Publish.current?(@meeting.reload)
    item.update!(title: "Harbor repair bid")
    URI.stub(:open, ->(*) { StringIO.new("publisher corrected this agenda") }) { Documents::DownloadJob.perform_now(agenda.id) }
    refute Minutes::Publish.current?(@meeting.reload)
  ensure
    AuditEvent.where(actor_id: actor.id).delete_all if actor
    User.where(id: actor&.id).delete_all
  end

  test "an explicit later agenda repair preserves the existing publication and rejects unheld meetings" do
    @meeting.update!(starts_at: Time.zone.local(2025, 7, 21, 18))
    batch = CouncilHistory::Batch.new([])
    with_transport { batch.repair_saved(@meeting, stages: [ "facts" ]) }
    publication_id = @meeting.reload.minutes_publication_id
    vote_ids = @meeting.motions.sole.votes.order(:id).ids
    attendance_ids = @meeting.meeting_attendances.order(:id).ids
    agenda = @meeting.meeting_documents.create!(document_type: "agenda_pdf", source_url: "https://example.test/later-agenda.pdf")
    URI.stub(:open, ->(*) { StringIO.new("later agenda PDF") }) { Documents::DownloadJob.perform_now(agenda.id) }
    @meeting.agenda_items.create!(number: "7.", title: "Harbor repair bid", kind: "item", order_index: 1)
    actor = User.create!(email_address: "later-agenda@example.test", admin: true, status: "active")
    review = -> { CouncilHistory::ReviewedFacts.preserve_published_votes!(@meeting, actor: actor, agenda: agenda, later_repair: true) }
    refute Minutes::Publish.current?(@meeting.reload)
    2.times do
      review.call
      assert Minutes::Publish.current?(@meeting.reload)
      with_transport { batch.repair_saved(@meeting, stages: [ "facts" ]) }
    end
    assert_equal publication_id, @meeting.reload.minutes_publication_id
    assert_equal vote_ids, @meeting.motions.sole.votes.order(:id).ids
    assert_equal attendance_ids, @meeting.meeting_attendances.order(:id).ids
    assert_equal 2, @calls.size
    assert_equal 1, AuditEvent.where(action: "council_history.review_supplemental_agenda", subject: @meeting).count
    assert_raises(ArgumentError) { CouncilHistory::ReviewedFacts.preserve_published_votes!(@meeting, actor: actor, agenda: agenda) }
    @meeting.update!(status: "cancelled")
    assert_raises(ArgumentError, &review)
    @meeting.update!(status: "scheduled", starts_at: 1.hour.from_now)
    assert_raises(ArgumentError, &review)
  ensure
    AuditEvent.where(actor_id: actor.id).delete_all if actor
    User.where(id: actor&.id).delete_all
  end

  test "a partial legacy meeting fills the missing attendance and preserves each accepted vote on replay" do
    @meeting.update!(starts_at: Time.zone.local(2025, 7, 8, 18))
    member = Member.find_or_create_by!(name: "Alex Budget")
    motion = @meeting.motions.create!(description: "Previously reviewed decision", outcome: "passed")
    vote = motion.votes.create!(member: member, value: "no")
    prior = vote.attributes
    batch = CouncilHistory::Batch.new([])
    2.times { with_transport { batch.repair_saved(@meeting.reload, stages: [ "facts" ]) } }
    assert_equal 1, @calls.size
    assert_equal "attendance", CouncilHistoryRequest.where(meeting_id: @meeting.id).sole.stage
    assert_equal prior, vote.reload.attributes
    assert_equal motion.id, @meeting.motions.sole.id
    assert @meeting.meeting_attendances.exists?(member: member, status: "present")
    assert_equal "processed", @meeting.reload.processing_state.fetch("committee_members_extraction_status")
  end

  test "a retained fact with different file bytes holds before buying another extraction" do
    @meeting.update!(starts_at: Time.zone.local(2025, 7, 8, 18))
    saved = { "url" => @document.source_url, "starts_at" => @meeting.starts_at.iso8601, "kind" => "votes", "sha256" => "f" * 64 }
    batch = CouncilHistory::Batch.new([], reviewed_facts: [ saved ])
    error = assert_raises(CouncilProfiles::ReserveAiSpend::Paused) do
      with_transport { batch.repair_saved(@meeting, stages: [ "facts" ]) }
    end
    assert_equal "reviewed_fact_source_needs_reconciliation", error.message
    assert_empty @calls
    assert_empty CouncilHistoryRequest.where(meeting_id: @meeting.id)
  end

  test "a later repair reuses saved facts without buying a summary or touching another stage" do
    @meeting.update!(starts_at: Time.zone.local(2025, 7, 8, 18))
    batch = CouncilHistory::Batch.new([])
    2.times { with_transport { batch.repair_saved(@meeting.reload, stages: [ "facts" ]) } }
    assert_equal 2, @calls.size
    assert_equal 2, @meeting.reload.motions.sole.votes.count
    assert_equal %w[attendance votes], CouncilHistoryRequest.where(meeting_id: @meeting.id, pilot: false).order(:stage).pluck(:stage)
    assert_equal "Existing accepted recap", @meeting.meeting_summaries.sole.content
    @meeting.update!(starts_at: Time.zone.local(2025, 7, 6, 18))
    assert_raises(ArgumentError) { batch.repair_saved(@meeting, stages: [ "facts" ]) }
  end
end
