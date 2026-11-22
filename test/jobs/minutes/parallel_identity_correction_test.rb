require "test_helper"
require "minitest/mock"
require "timeout"
require "open-uri"

class MinutesParallelIdentityCorrectionTest < ActiveJob::TestCase
  self.use_transactional_tests = false

  setup do
    suffix = SecureRandom.hex(8)
    @name = "Synthetic reviewer subject #{suffix}"
    @actor = User.create!(email_address: "reviewer-#{suffix}@example.test", admin: true)
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/reviews/#{suffix}")
    document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/reviews/#{suffix}.pdf")
    URI.stub(:open, ->(*) { StringIO.new("synthetic review source #{suffix}") }) { Documents::DownloadJob.perform_now(document.id) }
    passage = "The synthetic closing action passed; #{@name} voted yes."
    Documents::PublishText.new(document.reload).call(raw_pages: [ passage ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    @artifact = document.reload.current_source_version
    @text_version = document.current_text_version
    service = Object.new
    votes = { motions: [ { description: "Synthetic closing action", source_excerpt: passage, outcome: "passed", votes: [ { member: @name, value: "yes" } ] } ] }
    attendance = { voting_members_present: [ @name ], voting_members_absent: [], non_voting_staff: [], guests: [] }
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| votes.to_json }
    service.define_singleton_method(:extract_committee_members) { |*args, **kwargs| attendance.to_json }
    Ai::OpenAiService.stub :new, service do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    @observation = @meeting.reload.motions.sole.decision_observation
    @decision = @observation.council_decision
  end

  teardown do
    if @meeting&.persisted?
      stage_ids = @meeting.minutes_extractions.pluck(:id)
      publication_ids = @meeting.minutes_publications.pluck(:id)
      decision_ids = @meeting.council_decisions.pluck(:id)
      observation_ids = CouncilDecisionObservation.where(minutes_extraction_id: stage_ids).pluck(:id)
      @meeting.destroy!
      MinutesPublication.where(id: publication_ids).destroy_all
      CouncilDecisionAssignment.where(minutes_extraction_id: stage_ids).delete_all
      CouncilDecisionCorrection.where(observation_id: observation_ids).delete_all
      CouncilDecisionObservation.where(id: observation_ids).destroy_all
      CouncilDecision.where(id: decision_ids).destroy_all
      MinutesExtraction.where(id: stage_ids).destroy_all
    end
    @text_version&.destroy!
    @artifact&.destroy!
    Member.where(name: @name).destroy_all if @name
    User.where(id: @actor.id).delete_all if @actor
    perform_enqueued_jobs(only: ActiveStorage::PurgeJob)
  end

  test "concurrent reviews serialize and retrying the same request commits one audit" do
    Ai::OpenAiService.stub :new, ->(*) { flunk "Review must not invoke an AI provider" } do
      results = parallel_requests([
        { action: "assign", request_id: SecureRandom.uuid, expected_correction_id: nil },
        { action: "unassign", request_id: SecureRandom.uuid, expected_correction_id: nil }
      ])
      assert_equal 1, results.count { |result| result.is_a?(CouncilDecisionCorrection) }
      assert_equal 1, results.count { |result| result.is_a?(CouncilDecisions::ResolveIdentity::Conflict) }
      first = results.find { |result| result.is_a?(CouncilDecisionCorrection) }
      ActiveRecord::Base.uncached do
        assert_equal [ first.id ], CouncilDecisionCorrection.where(observation: @observation).pluck(:id)
        assignment = @observation.reload.identity_assignment
        if first.after_decision_id
          assert_equal first.after_decision_id, assignment.council_decision_id
        else
          assert_nil assignment.council_decision_id
        end
      end

      request = { action: "assign", request_id: SecureRandom.uuid, expected_correction_id: first.id }
      retries = parallel_requests([ request, request ])
      assert retries.all? { |result| result.is_a?(CouncilDecisionCorrection) }
      assert_equal 1, retries.map(&:id).uniq.size
      ActiveRecord::Base.uncached do
        assert_equal 2, CouncilDecisionCorrection.where(observation: @observation).count
        assert_equal retries.first.id, @observation.reload.identity_assignment.correction_id
        assert_equal @observation.id, CouncilDecision.find(@decision.id).current_observation&.id
      end
    end
  end

  private

  def parallel_requests(commands)
    entered, release = Queue.new, Queue.new
    workers = commands.map do |command|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          observation = CouncilDecisionObservation.find(@observation.id)
          actor = User.find(@actor.id)
          entered << true
          release.pop
          args = command[:action] == "assign" ? { decision: CouncilDecision.find(@decision.id), basis_observation: observation } : {}
          CouncilDecisions::ResolveIdentity.call(observation: observation, actor: actor, reason: "Synthetic concurrent identity review", **command, **args)
        rescue CouncilDecisions::ResolveIdentity::Conflict => e
          e
        end
      end
    end
    Timeout.timeout(10) do
      commands.size.times { entered.pop }
      commands.size.times { release << true }
      workers.map(&:value)
    end
  ensure
    workers&.size&.times { release << true }
    workers&.each { |worker| worker.join(10) }
  end
end
