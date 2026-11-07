require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesFactPublicationTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/facts")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/facts.pdf")
    revision("first", "Alex Example voted no. Blair Example was absent. The final motion failed.")
    @old_member = Member.create!(name: "Prior Example")
    @old_motion = @meeting.motions.create!(description: "Prior action", outcome: "passed")
    @meeting.meeting_attendances.create!(member: @old_member, status: "present", attendee_type: "voting_member")
    clear_enqueued_jobs
  end

  test "both stages publish together and known votes remain inspectable while attendance is pending" do
    run_votes
    assert_equal [ "Prior action" ], @meeting.motions.reload.pluck(:description)
    assert_equal [ @old_member.id ], @meeting.meeting_attendances.pluck(:member_id)
    stage = MinutesExtraction.find_by!(kind: "votes")
    assert_equal "completed", stage.status
    assert_equal "no", stage.data.fetch("motions").last.fetch("votes").first.fetch("value")

    run_attendance
    fresh = Meeting.find(@meeting.id)
    assert_equal [ "Opening action", "Final action" ], fresh.motions.order(:id).pluck(:description)
    assert_equal [ "Alex Example", "Blair Example" ], fresh.meeting_attendances.joins(:member).order("members.name").pluck("members.name")
    assert_equal [ "absent", "no" ], fresh.motions.order(:id).last.votes.pluck(:value).sort
    assert_equal @document.current_text_version.id, fresh.minutes_publication.votes_extraction.meeting_document_text_version_id
    assert_equal fresh.minutes_publication.votes_extraction.source_key, fresh.minutes_publication.attendance_extraction.source_key
  end

  test "unchanged stages do not dispatch providers or replace projected identities" do
    run_votes
    run_attendance
    ids = @meeting.motions.order(:id).pluck(:id)
    attendance_ids = @meeting.meeting_attendances.order(:id).pluck(:id)
    Ai::OpenAiService.stub :new, ->(*) { flunk "Unchanged inputs must not dispatch AI" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal ids, @meeting.motions.order(:id).pluck(:id)
    assert_equal attendance_ids, @meeting.meeting_attendances.order(:id).pluck(:id)
    assert_equal 2, MinutesExtraction.count
    assert_equal 1, MinutesPublication.count
  end

  test "late votes cannot mix with attendance from a revised source" do
    service = Object.new
    callback = -> {
      revision("second", "Alex Example voted yes. Blair Example attended. Revised final action passed.")
      run_votes(value: "yes", outcome: "passed")
      run_attendance(absent: false)
      votes_response.to_json
    }
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| callback.call }
    Ai::OpenAiService.stub(:new, service) { ExtractVotesJob.perform_now(@meeting.id) }
    fresh = Meeting.find(@meeting.id)
    assert_equal "passed", fresh.motions.order(:id).last.outcome
    assert_equal [ "yes" ], fresh.motions.order(:id).last.votes.pluck(:value)
    assert_equal [ "present" ], fresh.meeting_attendances.pluck(:status).uniq
    assert_equal @document.current_text_version.id, fresh.minutes_publication.votes_extraction.meeting_document_text_version_id
  end

  test "downloaded replacement without matching extracted text dispatches no AI" do
    URI.stub(:open, ->(*) { StringIO.new("new bytes awaiting parsing") }) { Documents::DownloadJob.perform_now(@document.id) }
    Ai::OpenAiService.stub :new, ->(*) { flunk "Old text must not be attributed to new bytes" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
    assert_equal 0, MinutesPublication.count
  end

  test "attendance first waits and absences are explicitly derived from the matching roll call" do
    previous_time = @meeting.reload.updated_at
    run_attendance
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
    assert_equal [ @old_member.id ], @meeting.meeting_attendances.pluck(:member_id)
    assert_equal previous_time, @meeting.reload.updated_at
    run_votes
    final = @meeting.motions.order(:id).last
    assert_equal [ [ "Alex Example", "no", "explicit" ], [ "Blair Example", "absent", "attendance_derived" ] ],
      final.votes.joins(:member).order("members.name").pluck("members.name", :value, :evidence_basis)
  end

  test "completed source stages survive a failed publication and retry without AI" do
    run_votes
    callback = -> { raise "synthetic second motion failure" if description == "Final action" }
    Motion.set_callback(:create, :before, callback)
    begin
      assert_raises(RuntimeError) { run_attendance }
    ensure
      Motion.skip_callback(:create, :before, callback)
    end
    assert_equal [ "Prior action" ], @meeting.motions.reload.pluck(:description)
    assert_equal [ @old_member.id ], @meeting.meeting_attendances.pluck(:member_id)
    assert_equal 0, MinutesPublication.count
    assert_equal [ "completed" ], MinutesExtraction.distinct.pluck(:status)
    Ai::OpenAiService.stub :new, ->(*) { flunk "Publication retry must reuse both completed stages" } do
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_equal [ "Opening action", "Final action" ], @meeting.motions.reload.order(:id).pluck(:description)
    assert_equal 1, MinutesPublication.count
  end

  test "duplicate in-flight work cannot make another provider request" do
    calls = 0
    service = Object.new
    response = votes_response.to_json
    id = @meeting.id
    service.define_singleton_method(:extract_votes) do |*args, **kwargs|
      calls += 1
      ExtractVotesJob.perform_now(id)
      response
    end
    with_provider(service) { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal 1, calls
    assert_equal 1, MinutesExtraction.find_by!(kind: "votes").attempts
    run_attendance
    assert_equal 1, MinutesPublication.count
  end

  test "invalid output is bounded and cannot turn an unsupported vote into abstention" do
    bad = votes_response
    bad["motions"].last["votes"].first["value"] = "unknown"
    calls = 0
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| calls += 1; bad.to_json }
    with_provider(service) { 3.times { ExtractVotesJob.perform_now(@meeting.id) } }
    assert_equal 2, calls
    assert_equal "failed", MinutesExtraction.find_by!(kind: "votes").status
    assert_equal "unknown", MinutesExtraction.find_by!(kind: "votes").data["motions"].last["votes"].first["value"]
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
    assert_equal 0, Vote.where(value: "abstain").count
  end

  test "uncertain provider outcome is retained without an automatic retry" do
    calls = 0
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| calls += 1; raise Timeout::Error }
    with_provider(service) { 2.times { ExtractVotesJob.perform_now(@meeting.id) } }
    stage = MinutesExtraction.find_by!(kind: "votes")
    assert_equal "uncertain", stage.status
    assert_equal 1, calls
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
    assert_nil stage.data
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
  end

  test "oversized minutes stop before dispatch instead of dropping the closing action" do
    revision("large", "x " * (Ai::OpenAiService::MAX_MINUTES_CHARS / 2) + "FINAL ACTION")
    Ai::OpenAiService.stub :new, ->(*) { flunk "Oversized source must not dispatch" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal [ "oversized" ], MinutesExtraction.distinct.pluck(:status)
    assert_equal [ 0 ], MinutesExtraction.distinct.pluck(:attempts)
    assert_includes MinutesExtraction.first.source_text, "FINAL ACTION"
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
  end

  test "nightly repair recovers only missing or changed stages without a new schedule" do
    run_votes
    clear_enqueued_jobs
    Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    assert_enqueued_with job: ExtractCommitteeMembersJob, args: [ @meeting.id ]
    assert_no_enqueued_jobs only: ExtractVotesJob
    assert_no_enqueued_jobs only: SummarizeMeetingJob
    run_attendance
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
    assert_not Minutes::Pipeline.needed?(@meeting, "attendance")
    URI.stub(:open, ->(*) { StringIO.new("changed bytes with missing parser trigger") }) { Documents::DownloadJob.perform_now(@document.id) }
    clear_enqueued_jobs
    Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    assert_enqueued_with job: Documents::AnalyzePdfJob, args: [ @document.id ]
    assert_no_enqueued_jobs only: ExtractVotesJob
    assert_no_enqueued_jobs only: ExtractCommitteeMembersJob
  end

  test "agenda revision invalidates votes but reuses the same attendance source" do
    run_votes
    run_attendance
    attendance = MinutesExtraction.find_by!(kind: "attendance")
    @meeting.agenda_items.create!(title: "New agenda context", number: "1", order_index: 1)
    assert Minutes::Pipeline.needed?(@meeting.reload, "votes")
    assert_not Minutes::Pipeline.needed?(@meeting, "attendance")
    run_votes
    fresh = @meeting.reload.minutes_publication
    assert_equal attendance.id, fresh.attendance_extraction_id
    assert_equal 1, MinutesExtraction.where(kind: "attendance").count
    assert_equal 2, MinutesPublication.count
  end

  test "member merge and cached replay preserve the canonical person" do
    run_votes
    run_attendance
    original = Member.find_by!(name: "Alex Example")
    target = Member.create!(name: "Alex Canonical")
    original.merge_into!(target)
    Ai::OpenAiService.stub :new, ->(*) { flunk "Merge must not re-extract an unchanged source" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal [ target.id ], @meeting.motions.order(:id).last.votes.where(value: "no").pluck(:member_id)
    assert @meeting.meeting_attendances.exists?(member: target)
    assert_equal "Alex Example", @meeting.reload.minutes_publication.votes_extraction.data["motions"].last["votes"].first["member"]
    @meeting.agenda_items.create!(number: "1", title: "Corrected agenda context", order_index: 1)
    run_votes
    assert_equal [ target.id ], @meeting.motions.order(:id).last.votes.where(value: "no").pluck(:member_id)
    assert @meeting.meeting_attendances.exists?(member: target)
  end

  test "retained stages survive source removal and cannot be silently replaced" do
    run_votes
    run_attendance
    publication = @meeting.reload.minutes_publication
    stage = publication.votes_extraction
    assert_not stage.update(data: { "motions" => [] })
    assert_equal "Final action", stage.reload.data["motions"].last["description"]
    @document.destroy!
    assert_not Minutes::Publish.current?(@meeting.reload)
    assert_equal stage.source_text, stage.meeting_document_text_version.extracted_text
    @meeting.destroy!
    assert_nil publication.reload.meeting_id
    assert_nil stage.reload.meeting_id
    assert_equal "Final action", stage.data["motions"].last["description"]
  end

  test "summary context excludes old motions until the current source is jointly published" do
    run_votes
    run_attendance
    job = SummarizeMeetingJob.new
    assert_includes job.send(:motion_context_for, @meeting.reload), "Final action"
    revision("replacement", "Revised closing action and roll call.")
    assert_not_includes job.send(:motion_context_for, @meeting.reload), "Final action"
    assert_includes job.send(:motion_context_for, @meeting), "pending"
  end

  test "prompt revision is pinned and invalidates only its own stage" do
    seed_prompt_templates
    original = PromptTemplate.find_by!(key: "extract_votes")
    original_instructions = original.instructions
    callback = ->(**kwargs) {
      original.update!(instructions: original.instructions + " Revised validation rule.")
      assert_equal original_instructions, kwargs.fetch(:template).instructions
      votes_response.to_json
    }
    service = Object.new
    service.define_singleton_method(:extract_votes) { |text, **kwargs| callback.call(**kwargs) }
    with_provider(service) { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
    run_attendance
    assert_equal [ "Prior action" ], @meeting.motions.pluck(:description)
    run_votes
    assert_equal [ "Opening action", "Final action" ], @meeting.motions.order(:id).pluck(:description)
    assert_equal 1, MinutesExtraction.where(kind: "attendance").count
    assert_equal 2, MinutesExtraction.where(kind: "votes").count
  end

  test "a meeting date correction republishes deterministic context without another AI call" do
    run_votes
    run_attendance
    first = @meeting.reload.minutes_publication
    @meeting.update!(starts_at: @meeting.starts_at - 1.day)
    assert Minutes::Pipeline.needed?(@meeting.reload, "votes")
    Ai::OpenAiService.stub :new, ->(*) { flunk "Date arithmetic must not re-extract unchanged source text" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    current = @meeting.reload.minutes_publication
    assert_not_equal first.id, current.id
    assert_equal first.votes_extraction_id, current.votes_extraction_id
    assert_equal first.attendance_extraction_id, current.attendance_extraction_id
    assert_not_equal first.projection_context, current.projection_context
    assert_equal 2, MinutesExtraction.count
  end

  private

  def revision(bytes, text)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: [ text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
  end

  def votes_response(value: "no", outcome: "failed")
    { "motions" => [
      { "description" => "Opening action", "outcome" => "passed", "votes" => [] },
      { "description" => "Final action", "outcome" => outcome, "votes" => [ { "member" => "Alex Example", "value" => value } ] }
    ] }
  end

  def run_votes(value: "no", outcome: "failed")
    response = votes_response(value: value, outcome: outcome).to_json
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| response }
    with_provider(service) { ExtractVotesJob.perform_now(@meeting.id) }
  end

  def run_attendance(absent: true)
    response = { voting_members_present: [ "Alex Example", *(absent ? [] : [ "Blair Example" ]) ],
      voting_members_absent: absent ? [ "Blair Example" ] : [], non_voting_staff: [], guests: [] }.to_json
    service = Object.new
    service.define_singleton_method(:extract_committee_members) { |*args, **kwargs| response }
    with_provider(service) { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
  end

  def with_provider(service)
    original = Ai::OpenAiService.method(:new)
    Ai::OpenAiService.define_singleton_method(:new) { |*args| service }
    yield
  ensure
    Ai::OpenAiService.define_singleton_method(:new, original)
  end
end
