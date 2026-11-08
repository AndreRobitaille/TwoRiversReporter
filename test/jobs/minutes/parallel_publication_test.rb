require "test_helper"
require "minitest/mock"
require "timeout"
require "open-uri"

class MinutesParallelPublicationTest < ActiveJob::TestCase
  # Workers must observe committed input using different database connections.
  self.use_transactional_tests = false

  test "parallel jobs claim once and publish one compatible set through real database locks" do
    previous_template_ids = PromptTemplate.pluck(:id)
    seed_prompt_templates
    created_template_ids = PromptTemplate.where.not(id: previous_template_ids).pluck(:id)
    suffix = SecureRandom.hex(8)
    names = [ "Parallel Alex #{suffix}", "Parallel Blair #{suffix}" ]
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/parallel/#{suffix}")
    document = meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/parallel.pdf")
    URI.stub(:open, ->(*) { StringIO.new("synthetic parallel source") }) { Documents::DownloadJob.perform_now(document.id) }
    passage = "The closing action passed: #{names.join(' and ')} voted yes."
    Documents::PublishText.new(document.reload).call(raw_pages: [ "#{names.join(' and ')} attended. #{passage}" ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    artifact = document.reload.current_source_version
    text_version = document.current_text_version
    meeting.motions.create!(description: "Prior action", outcome: "failed")
    entered, release = Queue.new, Queue.new
    calls = Hash.new(0)
    mutex = Mutex.new
    client = Object.new
    responses = {
      extract_votes: { motions: [ { description: "Parallel closing action", source_excerpt: passage, outcome: "passed", votes: names.map { |name| { member: name, value: "yes" } } } ] },
      extract_committee_members: { voting_members_present: names, voting_members_absent: [], non_voting_staff: [], guests: [] }
    }
    client.define_singleton_method(:chat) do |parameters:|
      method = parameters[:messages].last[:content].include?("voting_members_present") ? :extract_committee_members : :extract_votes
      mutex.synchronize { calls[method] += 1 }
      entered << method
      release.pop
      { "choices" => [ { "message" => { "content" => responses.fetch(method).to_json }, "finish_reason" => "stop" } ],
        "usage" => { "prompt_tokens" => 23, "completion_tokens" => 19, "total_tokens" => 42 } }
    end
    workers = []
    start_job = ->(job) do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { job.perform_now(meeting.id) }
      end
      workers.last
    end
    OpenAI::Client.stub :new, client do
      Timeout.timeout(10) do
        start_job.call(ExtractVotesJob)
        assert_equal :extract_votes, entered.pop
        # The duplicate returns while the first request is still in flight.
        start_job.call(ExtractVotesJob).value
        start_job.call(ExtractCommitteeMembersJob)
        assert_equal :extract_committee_members, entered.pop
        assert_equal [ "Prior action" ], Meeting.find(meeting.id).motions.pluck(:description)
        ActiveRecord::Base.uncached do
          receipts = MinutesRequest.joins(:minutes_extraction).where(minutes_extractions: { meeting_id: meeting.id })
          assert_equal 2, receipts.count
          assert_equal [ "dispatched" ], receipts.distinct.pluck(:status)
        end
        2.times { release << true }
        workers.each(&:value)
      end
    end
    # A later request has a fresh query cache; the observer queried these rows
    # before either worker committed on its separate connection.
    ActiveRecord::Base.uncached do
      fresh = Meeting.find(meeting.id)
      assert_equal({ extract_votes: 1, extract_committee_members: 1 }, calls)
      assert_equal [ "Parallel closing action" ], fresh.motions.pluck(:description)
      assert_equal names.sort, fresh.motions.first.votes.joins(:member).pluck("members.name").sort
      assert_equal names.sort, fresh.meeting_attendances.joins(:member).pluck("members.name").sort
      assert_equal 1, fresh.minutes_publications.count
      assert_equal 2, fresh.minutes_extractions.count
      receipts = MinutesRequest.where(minutes_extraction_id: fresh.minutes_extractions.select(:id))
      assert_equal 2, receipts.count
      assert_equal [ "received" ], receipts.distinct.pluck(:status)
      assert_equal 38, receipts.sum { |receipt| receipt.usage.fetch("output_tokens") }
      assert_equal [ 4_000 ], receipts.map { |receipt| receipt.request_parameters.fetch("max_completion_tokens") }.uniq
      assert_equal fresh.minutes_publication.votes_extraction.source_key, fresh.minutes_publication.attendance_extraction.source_key
      assert_equal "processed", fresh.processing_state["votes_extraction_status"]
      assert_equal "processed", fresh.processing_state["committee_members_extraction_status"]
      observation = fresh.motions.sole.decision_observation
      assert_equal "introduced", observation.identity_status
      assert_equal 1, fresh.council_decisions.count
      assert_equal observation.id, observation.council_decision.current_observation.id
    end
  ensure
    workers&.size&.times { release << true }
    workers&.each { |worker| worker.join(10) }
    if meeting&.persisted?
      stage_ids = meeting.minutes_extractions.pluck(:id)
      publication_ids = meeting.minutes_publications.pluck(:id)
      decision_ids = meeting.council_decisions.pluck(:id)
      meeting.destroy!
      MinutesPublication.where(id: publication_ids).destroy_all
      CouncilDecisionAssignment.where(minutes_extraction_id: stage_ids).delete_all
      CouncilDecisionObservation.where(minutes_extraction_id: stage_ids).destroy_all
      CouncilDecision.where(id: decision_ids).destroy_all
      MinutesRequest.where(minutes_extraction_id: stage_ids).delete_all
      MinutesExtraction.where(id: stage_ids).destroy_all
      PromptRun.where(source_type: "Meeting", source_id: meeting.id).delete_all
    end
    text_version&.destroy!
    artifact&.destroy!
    Member.where(name: names).destroy_all if names
    PromptTemplate.where(id: created_template_ids).destroy_all if created_template_ids
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end
end
