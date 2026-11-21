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
      with_transport { batch.call }
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
