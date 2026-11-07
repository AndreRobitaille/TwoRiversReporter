require "test_helper"
require "minitest/mock"
require "timeout"
require "open-uri"

class MinutesParallelPublicationTest < ActiveJob::TestCase
  # Workers must observe committed input using different database connections.
  self.use_transactional_tests = false

  test "parallel jobs claim once and publish one compatible set through real database locks" do
    suffix = SecureRandom.hex(8)
    names = [ "Parallel Alex #{suffix}", "Parallel Blair #{suffix}" ]
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/parallel/#{suffix}")
    document = meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/parallel.pdf")
    URI.stub(:open, ->(*) { StringIO.new("synthetic parallel source") }) { Documents::DownloadJob.perform_now(document.id) }
    Documents::PublishText.new(document.reload).call(raw_pages: [ "Both synthetic participants attended. The closing action passed." ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    artifact = document.reload.current_source_version
    text_version = document.current_text_version
    meeting.motions.create!(description: "Prior action", outcome: "failed")
    entered, release = Queue.new, Queue.new
    calls = Hash.new(0)
    mutex = Mutex.new
    service = Object.new
    responses = {
      extract_votes: { motions: [ { description: "Parallel closing action", outcome: "passed", votes: names.map { |name| { member: name, value: "yes" } } } ] },
      extract_committee_members: { voting_members_present: names, voting_members_absent: [], non_voting_staff: [], guests: [] }
    }
    responses.each do |method, response|
      service.define_singleton_method(method) do |*args, **kwargs|
        mutex.synchronize { calls[method] += 1 }
        entered << method
        release.pop
        response.to_json
      end
    end
    workers = []
    start_job = ->(job) do
      workers << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection { job.perform_now(meeting.id) }
      end
      workers.last
    end
    Ai::OpenAiService.stub :new, service do
      Timeout.timeout(10) do
        start_job.call(ExtractVotesJob)
        assert_equal :extract_votes, entered.pop
        # The duplicate returns while the first request is still in flight.
        start_job.call(ExtractVotesJob).value
        start_job.call(ExtractCommitteeMembersJob)
        assert_equal :extract_committee_members, entered.pop
        assert_equal [ "Prior action" ], Meeting.find(meeting.id).motions.pluck(:description)
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
      assert_equal fresh.minutes_publication.votes_extraction.source_key, fresh.minutes_publication.attendance_extraction.source_key
      assert_equal "processed", fresh.processing_state["votes_extraction_status"]
      assert_equal "processed", fresh.processing_state["committee_members_extraction_status"]
    end
  ensure
    workers&.size&.times { release << true }
    workers&.each { |worker| worker.join(10) }
    if meeting&.persisted?
      stage_ids = meeting.minutes_extractions.pluck(:id)
      publication_ids = meeting.minutes_publications.pluck(:id)
      meeting.destroy!
      MinutesPublication.where(id: publication_ids).destroy_all
      MinutesExtraction.where(id: stage_ids).destroy_all
    end
    text_version&.destroy!
    artifact&.destroy!
    Member.where(name: names).destroy_all if names
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end
end
