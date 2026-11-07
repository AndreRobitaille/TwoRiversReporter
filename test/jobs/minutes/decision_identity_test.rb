require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesDecisionIdentityTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/decisions")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/decisions.pdf")
    @agenda = @meeting.agenda_items.create!(number: "5A", title: "Synthetic garden amendment", order_index: 1)
    @excerpts = [ "Motion to deny the synthetic amendment failed; Alex Example voted no.",
      "Motion to adopt the synthetic amendment passed; Alex Example voted yes." ]
    revision("first", @excerpts)
  end

  test "separate decisions in one agenda item retain opaque identities through replay and source revision" do
    publish
    first_motions = @meeting.motions.order(:id).to_a
    first_observations = first_motions.map { |motion| motion.try(:decision_observation) }
    assert first_observations.all?(&:present?), "Published decisions need retained observations independent of Motion IDs"
    decisions = first_observations.map(&:council_decision)
    assert_equal 2, decisions.map(&:public_id).uniq.size
    decisions.each { |decision| assert_match(/\A[0-9a-f-]{36}\z/, decision.public_id) }
    assert_equal %w[introduced introduced], first_observations.map(&:identity_status)
    assert_equal %w[no yes], first_observations.map { |observation| observation.data.fetch("votes").sole.fetch("value") }
    Ai::OpenAiService.stub :new, ->(*) { flunk "Replay must not dispatch providers" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      @meeting.update!(starts_at: @meeting.starts_at - 1.day)
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_equal first_observations.map(&:id), @meeting.motions.order(:id).map(&:decision_observation_id)
    assert_equal 2, CouncilDecision.count
    assert_equal 2, CouncilDecisionObservation.count

    revision("second", [ "Corrected document heading.", *@excerpts ])
    publish(descriptions: [ "Reject amendment", "Adopt amendment" ])
    current = @meeting.motions.order(:id).map(&:decision_observation)
    assert_equal decisions.map(&:id), current.map(&:council_decision_id)
    assert_equal %w[matched matched], current.map(&:identity_status)
    assert_equal 4, CouncilDecisionObservation.count
    assert_not_equal first_motions.map(&:id), @meeting.motions.order(:id).pluck(:id)
    assert_equal current.map(&:id), decisions.map { |decision| CouncilDecision.find_by!(public_id: decision.public_id).current_observation.id }
    assert_equal [ "extracted" ], current.map(&:evidence_status).uniq
    assert_equal @excerpts, first_observations.map { |observation| observation.reload.data["description"] }
    assert_not_equal first_observations.first.minutes_extraction.meeting_document_text_version_id,
      current.first.minutes_extraction.meeting_document_text_version_id
  end

  test "restoring an identical source reuses its observations and stable references without AI" do
    publish
    original = @meeting.motions.order(:id).map(&:decision_observation)
    revision("revised-heading", [ "Revised heading", *@excerpts ])
    publish
    revision("first", @excerpts)
    Ai::OpenAiService.stub :new, ->(*) { flunk "Identical retained inputs must be reused" } do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal original.map(&:id), @meeting.motions.order(:id).pluck(:decision_observation_id)
    assert_equal original.map(&:council_decision_id), @meeting.motions.order(:id).map { |motion| motion.council_decision.id }
    assert_equal 2, CouncilDecision.count
    assert_equal 4, CouncilDecisionObservation.count
    assert_equal 2, @document.source_versions.count
  end

  test "changed evidence withdraws the old current reference while unrelated decisions advance" do
    publish
    original = @meeting.motions.order(:id).map(&:decision_observation)
    changed = "Motion to deny a different synthetic amendment passed; Alex Example voted yes."
    revision("changed", [ changed, @excerpts.last ])
    publish(excerpts: [ changed, @excerpts.last ])
    current = @meeting.motions.order(:id).map(&:decision_observation)
    assert_equal "unresolved", current.first.identity_status
    assert_nil current.first.council_decision_id
    assert_includes current.first.candidate_decision_ids, original.first.council_decision_id
    assert_nil CouncilDecision.find(original.first.council_decision_id).current_observation
    assert_equal "matched", current.last.identity_status
    assert_equal original.last.council_decision_id, current.last.council_decision_id
    assert_equal 2, CouncilDecision.count
    assert_equal @excerpts.first, original.first.reload.data["source_excerpt"]
    assert_raises(ActiveRecord::ReadonlyAttributeError) { original.first.update!(data: {}) }
  end

  test "reordered passages require identity resolution rather than swapping stable references" do
    publish
    old_ids = @meeting.motions.order(:id).map { |motion| motion.decision_observation.council_decision_id }
    revision("reordered", @excerpts.reverse)
    publish(excerpts: @excerpts.reverse)
    current = @meeting.motions.order(:id).map(&:decision_observation)
    assert_equal %w[unresolved unresolved], current.map(&:identity_status)
    assert_equal [ nil, nil ], current.map(&:council_decision_id)
    assert current.all? { |observation| observation.candidate_decision_ids.any? }
    assert old_ids.all? { |id| CouncilDecision.find(id).current_observation.nil? }
    assert_equal 2, CouncilDecision.count
  end

  test "duplicate excerpt attribution acquires no guessed identity" do
    publish(excerpts: [ @excerpts.first, @excerpts.first ])
    observations = @meeting.motions.order(:id).map(&:decision_observation)
    assert_equal %w[unresolved unresolved], observations.map(&:identity_status)
    assert_equal [ "duplicate_excerpt_attribution" ], observations.map(&:reason).uniq
    assert_equal 0, CouncilDecision.count
    assert_equal 2, observations.size
  end

  test "unsupported agenda references and missing source excerpts acquire no guessed identity" do
    publish(agenda_ref: "invented agenda")
    assert_equal [ "unresolved_agenda_reference" ], @meeting.motions.map { |motion| motion.decision_observation.reason }.uniq
    assert_equal 0, CouncilDecision.count
    revision("missing-quotes", [ "New heading", *@excerpts ])
    publish(excerpts: [ nil, nil ], descriptions: @excerpts)
    assert_equal [ "missing_excerpt" ], @meeting.motions.map { |motion| motion.decision_observation.reason }.uniq
    assert_equal 0, CouncilDecision.count
    assert_equal 4, CouncilDecisionObservation.count
  end

  test "first supported evidence establishes identities without claiming to match older unlocated records" do
    publish(excerpts: [ nil, nil ], descriptions: @excerpts)
    unlocated = @meeting.motions.map(&:decision_observation)
    assert_equal 0, CouncilDecision.count
    revision("first-supported", [ "Supported replacement", *@excerpts ])
    publish
    assert_equal 2, CouncilDecision.count
    assert_equal [ "introduced" ], @meeting.motions.map { |motion| motion.decision_observation.identity_status }.uniq
    assert unlocated.all? { |observation| observation.reload.council_decision_id.nil? }
    assert_equal [ "unresolved" ], unlocated.map(&:identity_status).uniq
  end

  test "replacing agenda row IDs preserves exact context and decision identity" do
    publish
    identities = @meeting.motions.order(:id).map { |motion| motion.council_decision.public_id }
    @agenda.destroy!
    @meeting.agenda_items.create!(number: "5A", title: "Synthetic garden amendment", order_index: 1)
    publish
    assert_equal identities, @meeting.motions.order(:id).map { |motion| motion.council_decision.public_id }
    assert_equal 2, CouncilDecision.count
    assert_equal 4, CouncilDecisionObservation.count
  end

  test "filtered unseconded motions do not shift the retained source sequence" do
    unseconded = "Motion made by Alex Example to table the synthetic amendment, no second."
    revision("unseconded", [ unseconded, *@excerpts ])
    publish(excerpts: [ unseconded, *@excerpts ], descriptions: [ "Motion to table", *@excerpts ])
    observations = @meeting.motions.order(:id).map(&:decision_observation)
    assert_equal [ 2, 3 ], observations.map(&:sequence)
    assert_equal @excerpts, observations.map { |observation| observation.data["source_excerpt"] }
    assert_equal 2, CouncilDecision.count
    assert_equal 3, @meeting.minutes_publication.votes_extraction.data["motions"].size
  end

  test "late source extraction cannot replace stable references from a newer publication" do
    publish
    identities = @meeting.motions.order(:id).map { |motion| motion.council_decision.public_id }
    revision("intermediate", [ "Intermediate heading", *@excerpts ])
    intermediate = @document.current_text_version
    callback = -> do
      revision("newest", [ "Newest heading", *@excerpts ])
      publish
      votes_data(descriptions: [ "Late denial", "Late adoption" ]).to_json
    end
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| callback.call }
    with_provider(service) { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal identities, @meeting.motions.order(:id).map { |motion| motion.council_decision.public_id }
    assert_equal @excerpts, @meeting.motions.order(:id).pluck(:description)
    assert_equal 4, CouncilDecisionObservation.count
    late_stage = @meeting.minutes_extractions.find_by!(kind: "votes", meeting_document_text_version: intermediate)
    assert_equal "completed", late_stage.status
    assert_equal 0, late_stage.council_decision_observations.count
  end

  test "member merge and source removal preserve decision references and raw attribution" do
    publish
    identities = @meeting.motions.order(:id).map { |motion| motion.decision_observation.council_decision.public_id }
    member = Member.find_by!(name: "Alex Example")
    canonical = Member.create!(name: "Alex Canonical")
    member.merge_into!(canonical)
    revision("after-merge", [ "New heading", *@excerpts ])
    publish
    assert_equal [ canonical.id ], Vote.joins(:motion).where(motions: { meeting_id: @meeting.id }).distinct.pluck(:member_id)
    assert_equal identities, @meeting.motions.order(:id).map { |motion| motion.decision_observation.council_decision.public_id }
    @document.destroy!
    latest = identities.map { |id| CouncilDecision.find_by!(public_id: id).current_observation }
    assert_equal [ "Alex Example" ], latest.flat_map { |observation| observation.data["votes"].map { |vote| vote["member"] } }.uniq
    @meeting.destroy!
    identities.each do |id|
      decision = CouncilDecision.find_by!(public_id: id)
      assert_nil decision.current_observation
      assert_equal 2, decision.observations.count
      assert decision.observations.all? { |observation| observation.minutes_extraction.meeting_document_text_version.present? }
    end
  end

  test "failed publication rolls back new identities and observations and retries without AI" do
    run_stage(:extract_votes, votes_data)
    closing = @excerpts.last
    callback = -> { raise "synthetic second decision failure" if description == closing }
    Motion.set_callback(:create, :before, callback)
    begin
      assert_raises(RuntimeError) { run_stage(:extract_committee_members, attendance_data) }
    ensure
      Motion.skip_callback(:create, :before, callback)
    end
    assert_equal 0, CouncilDecision.count
    assert_equal 0, CouncilDecisionObservation.count
    assert_nil @meeting.reload.minutes_publication_id
    Ai::OpenAiService.stub :new, ->(*) { flunk "Publication retry must reuse completed extraction" } do
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_equal 2, CouncilDecision.count
    assert_equal 2, CouncilDecisionObservation.count
  end

  private

  def revision(bytes, pages)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: pages, page_count: pages.size, quality: "text", extractor_version: "synthetic_v1")
    @document.reload
  end

  def votes_data(excerpts: @excerpts, descriptions: excerpts, agenda_ref: "5A: Synthetic garden amendment")
    { motions: excerpts.each_with_index.map { |excerpt, index| { description: descriptions[index], source_excerpt: excerpt,
      agenda_item_ref: agenda_ref, outcome: index.zero? ? "failed" : "passed", votes: [ { member: "Alex Example", value: index.zero? ? "no" : "yes" } ] } } }
  end

  def attendance_data
    { voting_members_present: [ "Alex Example" ], voting_members_absent: [], non_voting_staff: [], guests: [] }
  end

  def publish(**kwargs)
    run_stage(:extract_votes, votes_data(**kwargs))
    run_stage(:extract_committee_members, attendance_data)
    @meeting.reload
  end

  def run_stage(method, data)
    service = Object.new
    service.define_singleton_method(method) { |*args, **kwargs| data.to_json }
    job = method == :extract_votes ? ExtractVotesJob : ExtractCommitteeMembersJob
    with_provider(service) { job.perform_now(@meeting.id) }
  end

  def with_provider(service)
    original = Ai::OpenAiService.method(:new)
    Ai::OpenAiService.define_singleton_method(:new) { |*args| service }
    yield
  ensure
    Ai::OpenAiService.define_singleton_method(:new, original)
  end
end
