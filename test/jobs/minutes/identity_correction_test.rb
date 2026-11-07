require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesIdentityCorrectionTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/correction")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/correction.pdf")
    @agenda = @meeting.agenda_items.create!(number: "5", title: "Synthetic amendment", order_index: 1)
    @excerpts = [ "Motion to deny the synthetic amendment failed; Alex Example voted no.",
      "Motion to adopt the synthetic amendment passed; Alex Example voted yes." ]
    @actor = User.create!(email_address: "identity-editor@example.test", admin: true)
    revision("original", @excerpts)
    publish
    @original = observations
  end

  test "publication retains effective identity independently of immutable extraction" do
    assert @original.all? { |observation| observation.respond_to?(:identity_assignment) && observation.identity_assignment.present? },
      "Identity review needs a current assignment without overwriting the original extraction basis"
    assert_equal @original.map(&:council_decision_id), @original.map { |observation| observation.identity_assignment.council_decision_id }
  end

  test "reviewed identity resolves an ambiguous record and survives replay without changing raw evidence" do
    revision("reversed", @excerpts.reverse)
    publish(excerpts: @excerpts.reverse)
    target = observations.first
    decision = @original.last.council_decision
    assert_nil decision.current_observation
    assert_equal "unresolved", target.identity_status
    correction = resolve(target, decision: decision, basis: @original.last)

    assert_equal target.id, CouncilDecision.find(decision.id).current_observation&.id
    assert_equal decision.id, @meeting.motions.order(:id).first.council_decision.id
    assert_equal "unresolved", target.reload.identity_status
    assert_nil target.council_decision_id
    assert_equal "extracted", target.evidence_status
    assert_equal @actor.id, correction.original_actor_id
    assert_equal "Match the retained opposing motion", correction.reason
    assert_nil correction.before_decision_id
    assert_equal decision.id, correction.after_decision_id
    assert_equal @original.last.id, correction.basis_observation_id
    assert_equal target.minutes_extraction.source_key, correction.evidence_manifest["source_key"]

    canonical = Member.create!(name: "Alex Canonical")
    Member.find_by!(name: "Alex Example").merge_into!(canonical)
    without_ai do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      @meeting.update!(starts_at: @meeting.starts_at - 1.day)
      ExtractVotesJob.perform_now(@meeting.id)
    end
    assert_equal target.id, CouncilDecision.find(decision.id).current_observation&.id
    assert_equal correction.id, target.reload.identity_assignment.correction_id
    assert_equal 1, CouncilDecisionCorrection.count
    assert_equal 2, CouncilDecision.count
    assert_equal [ canonical.id ], Vote.joins(:motion).where(motions: { meeting_id: @meeting.id }).distinct.pluck(:member_id)
    assert_equal "Alex Example", target.data.fetch("votes").sole.fetch("member")
  end

  test "review carries across unchanged retained evidence but changed source requires resolution again" do
    first = @original.first
    decision = first.council_decision
    correction = resolve(first, decision: decision, basis: first)
    @agenda.destroy!
    @agenda = @meeting.agenda_items.create!(number: "5", title: "Synthetic amendment", order_index: 1)
    publish
    carried = observations.first
    assert_not_equal first.id, carried.id
    assert_equal decision.id, carried.identity_assignment.council_decision_id
    assert_equal correction.id, carried.identity_assignment.correction_id
    assert_equal 1, CouncilDecisionCorrection.count

    revision("changed-source", [ "Corrected heading", *@excerpts ])
    publish
    current = observations
    assert_equal "identity_correction_source_changed", current.first.reason
    assert_nil current.first.identity_assignment.council_decision_id
    assert_nil CouncilDecision.find(decision.id).current_observation
    assert_equal @original.last.council_decision_id, current.last.identity_assignment.council_decision_id
    assert_equal correction.id, first.reload.identity_assignment.correction_id
    assert_equal first.data, correction.evidence_manifest["data"]
  end

  test "a changed extraction from the same source cannot silently reuse identity review" do
    first = @original.first
    resolve(first, decision: first.council_decision, basis: first)
    @agenda.destroy!
    @meeting.agenda_items.create!(number: "5", title: "Synthetic amendment", order_index: 1)
    publish(descriptions: [ "A different interpretation of the denial", @excerpts.last ])
    assert_equal "identity_correction_conflict", observations.first.reason
    assert_nil first.council_decision.current_observation
    assert_equal @original.last.council_decision_id, observations.last.identity_assignment.council_decision_id
  end

  test "unassignment is append only and old request retries cannot restore a revoked mapping" do
    first = @original.first
    decision = first.council_decision
    request_id = SecureRandom.uuid
    accepted = resolve(first, decision: decision, basis: first, request_id: request_id)
    withdrawn = resolve(first, action: "unassign", expected_correction_id: accepted.id, reason: "Identity is no longer established")
    assert_nil decision.current_observation
    assert_nil @meeting.motions.order(:id).first.council_decision
    assert_equal accepted.id, withdrawn.previous_correction_id
    assert_equal decision.id, withdrawn.before_decision_id
    assert_nil withdrawn.after_decision_id
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) do
      resolve(first, decision: decision, basis: first)
    end
    @agenda.destroy!
    @meeting.agenda_items.create!(number: "5", title: "Synthetic amendment", order_index: 1)
    publish
    assert_equal "identity_review_unassigned", observations.first.reason
    assert_equal withdrawn.id, observations.first.identity_assignment.correction_id
    assert_nil @meeting.motions.order(:id).first.council_decision
    replay = resolve(first, decision: decision, basis: first, request_id: request_id)
    assert_equal accepted.id, replay.id
    assert_equal withdrawn.id, first.reload.identity_assignment.correction_id
    assert_equal 2, CouncilDecisionCorrection.count
    assert_raises(ActiveRecord::ReadonlyAttributeError) { accepted.update!(reason: "Rewrite the audit") }
    assert_not accepted.destroy
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) do
      resolve(first, decision: decision, basis: first)
    end
    assert_equal 2, CouncilDecisionCorrection.count
  end

  test "unmatched new evidence can receive a reviewed identity without duplicating it on retry" do
    extra = "Motion to accept the synthetic report passed; Alex Example voted yes."
    revision("new-decision", [ *@excerpts, extra ])
    publish(excerpts: [ *@excerpts, extra ])
    added = observations.last
    assert_equal "unmatched_revision", added.reason
    request_id = SecureRandom.uuid
    correction = resolve(added, action: "introduce", request_id: request_id)
    assert_equal 3, CouncilDecision.count
    assert_equal added.id, correction.after_decision.current_observation.id
    assert_equal correction.id, resolve(added, action: "introduce", request_id: request_id).id
    assert_equal 3, CouncilDecision.count
  end

  test "unlocated evidence occupied identities and stale sources are rejected without an audit or assignment change" do
    first = @original.first
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) do
      resolve(first, decision: @original.last.council_decision, basis: @original.last)
    end
    assert_equal @original.map(&:council_decision_id), observations.map { |observation| observation.identity_assignment.council_decision_id }
    revision("pending-source", [ "New source", *@excerpts ])
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) do
      resolve(first, decision: first.council_decision, basis: first)
    end
    publish(excerpts: [ nil, nil ], descriptions: @excerpts)
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) { resolve(observations.first, action: "introduce") }
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) { resolve(observations.first, action: "unassign") }
    assert_equal 0, CouncilDecisionCorrection.count
    assert_equal 2, CouncilDecision.count
  end

  test "only an active administrator can review and request IDs cannot be reused for a different command" do
    first = @original.first
    request_id = SecureRandom.uuid
    correction = resolve(first, decision: first.council_decision, basis: first, request_id: request_id)
    assert_equal correction.id, first.reload.identity_assignment.correction_id
    [ User.create!(email_address: "reader@example.test", status: "active"),
      User.create!(email_address: "disabled-editor@example.test", admin: true, disabled_at: Time.current) ].each do |actor|
      assert_raises(CouncilDecisions::ResolveIdentity::NotAuthorized) do
        resolve(first, decision: first.council_decision, basis: first, actor: actor, expected_correction_id: correction.id)
      end
    end
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) do
      resolve(first, decision: first.council_decision, basis: first, request_id: request_id, reason: "A different command")
    end
    assert_equal 1, CouncilDecisionCorrection.count
  end

  test "failed assignment rolls back its audit and new identity so the same request can retry" do
    extra = "Motion to accept the synthetic report passed; Alex Example voted yes."
    revision("new-decision", [ *@excerpts, extra ])
    publish(excerpts: [ *@excerpts, extra ])
    added = observations.last
    request_id = SecureRandom.uuid
    callback = -> { raise "synthetic assignment failure" }
    CouncilDecisionAssignment.set_callback(:update, :before, callback)
    begin
      assert_raises(RuntimeError) { resolve(added, action: "introduce", request_id: request_id) }
    ensure
      CouncilDecisionAssignment.skip_callback(:update, :before, callback)
    end
    assert_equal 0, CouncilDecisionCorrection.count
    assert_equal 2, CouncilDecision.count
    assert_nil added.reload.identity_assignment.council_decision_id
    correction = resolve(added, action: "introduce", request_id: request_id)
    assert_equal correction.after_decision_id, added.reload.identity_assignment.council_decision_id
    assert_equal 1, CouncilDecisionCorrection.count
    assert_equal 3, CouncilDecision.count
  end

  test "source meeting and actor removal retain correction history without exposing a stale current reference" do
    first = @original.first
    decision = first.council_decision
    correction = resolve(first, decision: decision, basis: first)
    actor_id, email = @actor.id, @actor.email_address
    backup = User.create!(email_address: "remaining-editor@example.test", admin: true)
    backup.passkey_credentials.create!(external_id: SecureRandom.uuid, public_key: "synthetic-key", sign_count: 0)
    @actor.destroy!
    assert_nil correction.reload.actor
    assert_equal actor_id, correction.original_actor_id
    assert_equal email, correction.actor_email
    @document.destroy!
    assert_equal first.id, CouncilDecision.find(decision.id).current_observation&.id
    @meeting.destroy!
    assert_nil CouncilDecision.find(decision.id).current_observation
    assert_equal correction.id, first.reload.identity_assignment.correction_id
    assert correction.reload.observation.minutes_extraction.meeting_document_text_version.present?
    assert_equal "decision_identity_only", correction.evidence_manifest["review_scope"]
    correction.evidence_manifest["data"]["description"] = "Rewritten history"
    assert_not correction.valid?
    assert_equal first.data, correction.reload.evidence_manifest["data"]
  end

  test "a decision and basis from another meeting cannot be assigned" do
    other = Meeting.create!(body_name: "Other Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/other")
    foreign = CouncilDecision.create!(meeting: other, original_meeting_id: other.id)
    assert_raises(CouncilDecisions::ResolveIdentity::Conflict) do
      resolve(@original.first, decision: foreign, basis: @original.first)
    end
    assert_equal 0, CouncilDecisionCorrection.count
    assert_equal @original.first.council_decision_id, @original.first.reload.identity_assignment.council_decision_id
  end

  test "schema rollback refuses to discard reviewed history" do
    first = @original.first
    correction = resolve(first, decision: first.council_decision, basis: first)
    require Rails.root.join("db/migrate/20261107230000_create_council_decision_corrections")
    migration = CreateCouncilDecisionCorrections.new
    assert_raises(ActiveRecord::IrreversibleMigration) { migration.suppress_messages { migration.down } }
    assert_equal correction.id, first.reload.identity_assignment.correction_id
    assert CouncilDecisionCorrection.exists?(correction.id)
  end

  test "reviewed unassignment holds an unidentified record while unrelated first supported evidence advances" do
    prepare_unidentified_meeting
    rejected = observations.first
    correction = resolve(rejected, action: "unassign", reason: "No supported identity yet")
    assert_equal 0, @meeting.council_decisions.count
    @agenda.destroy!
    @meeting.agenda_items.create!(number: "5", title: "Synthetic amendment", order_index: 1)
    publish
    current = observations
    assert_equal %w[unresolved introduced], current.map(&:identity_status)
    assert_equal "identity_correction_conflict", current.first.reason
    assert_nil current.first.identity_assignment.council_decision_id
    assert_equal 1, @meeting.council_decisions.count
    assert_equal correction.id, rejected.reload.identity_assignment.correction_id
    assert_equal [ correction.id ], current.first.identity_assignment.conflicting_correction_ids
    revision("unidentified-revised", [ "Revised heading", *@excerpts ])
    publish
    assert_equal [ correction.id ], observations.first.identity_assignment.conflicting_correction_ids
    assert_nil observations.first.identity_assignment.council_decision_id
    assert_equal 1, @meeting.council_decisions.count
    accepted = resolve(observations.first, action: "introduce")
    assert_equal [ correction.id ], accepted.evidence_manifest["resolved_conflict_ids"]
    assert_empty observations.first.identity_assignment.conflicting_correction_ids
    assert_equal 2, @meeting.council_decisions.count
  end

  test "rewritten evidence cannot erase unresolved reviews by repeatedly resetting an empty identity baseline" do
    prepare_unidentified_meeting
    corrections = observations.map { |observation| resolve(observation, action: "unassign", reason: "Identity is unresolved") }
    assert_equal 0, @meeting.council_decisions.count
    replacements = [ "First replacement decision passed; Alex Example voted yes.", "Second replacement decision passed; Alex Example voted yes." ]
    2.times do |index|
      revision("rewritten-#{index}", [ "Replacement #{index}", *replacements ])
      publish(excerpts: replacements)
      assert_equal 0, @meeting.council_decisions.count
      assert_equal [ "identity_correction_conflict" ], observations.map(&:reason).uniq
      assert observations.all? { |observation| observation.identity_assignment.conflicting_correction_ids == corrections.map(&:id).sort }
    end
    assert_equal 2, CouncilDecisionCorrection.count
  end

  test "a review committed while a provider is in flight survives its later same-source publication" do
    original_stage = @meeting.reload.minutes_publication.votes_extraction
    first = @original.first
    seed_prompt_templates
    correction = nil
    callback = -> do
      correction = CouncilDecisions::ResolveIdentity.call(observation: first, action: "assign", actor: @actor,
        reason: "Review during extraction", expected_correction_id: nil, request_id: SecureRandom.uuid,
        decision: first.council_decision, basis_observation: first)
      original_stage.data.to_json
    end
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| callback.call }
    calls = 0
    Ai::OpenAiService.stub :new, ->(*) { calls += 1; service } do
      ExtractVotesJob.perform_now(@meeting.id, refresh: true)
    end
    current = observations.first
    assert_equal 1, calls
    assert_not_equal original_stage.id, current.minutes_extraction_id
    assert_equal correction.id, current.identity_assignment.correction_id
    assert_equal first.council_decision_id, current.identity_assignment.council_decision_id
    assert_equal current.id, CouncilDecision.find(first.council_decision_id).current_observation&.id
    assert_equal 1, CouncilDecisionCorrection.count
    assert_equal first.data, current.data
  end

  test "restoring a cached extraction cannot revive a mapping withdrawn for the same evidence" do
    first = @original.first
    accepted = resolve(first, decision: first.council_decision, basis: first)
    refresh_votes(first.minutes_extraction.data)
    replacement = observations.first
    assert_not_equal first.id, replacement.id
    assert_equal accepted.id, replacement.identity_assignment.correction_id
    withdrawn = resolve(replacement, action: "unassign", expected_correction_id: accepted.id)
    PromptTemplate.find_by!(key: "extract_votes").destroy!
    without_ai { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal first.id, observations.first.id
    assert_nil CouncilDecision.find(first.council_decision_id).current_observation
    assert_nil @meeting.motions.order(:id).first.council_decision
    assert_equal withdrawn.id, first.reload.identity_assignment.correction_id
    assert_equal 2, CouncilDecisionCorrection.count
  end

  test "a review holds both historical assignments when its target is occupied in a cached extraction" do
    first, second = @original
    changed = first.minutes_extraction.data.deep_dup
    changed["motions"][1]["description"] = "A revised interpretation of the second motion"
    refresh_votes(changed)
    current_first, current_second = observations
    resolve(current_second, action: "unassign")
    review = resolve(current_first, decision: second.council_decision, basis: second)
    assert_equal current_first.id, CouncilDecision.find(second.council_decision_id).current_observation&.id
    PromptTemplate.find_by!(key: "extract_votes").destroy!
    without_ai { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal @original.map(&:id), observations.map(&:id)
    assert_nil CouncilDecision.find(second.council_decision_id).current_observation
    assert observations.all? { |observation| observation.identity_assignment.conflicting_correction_ids.include?(review.id) }
    assert_equal [ nil, nil ], @meeting.motions.order(:id).map { |motion| motion.council_decision&.id }
    assert_equal 3, review.evidence_manifest.fetch("assignment_changes").size
  end

  test "review lineage survives when correspondence is lost and unrelated decisions still advance" do
    first = @original.first
    review = resolve(first, decision: first.council_decision, basis: first)
    @meeting.agenda_items.create!(number: "6", title: "Revised synthetic matter", order_index: 2)
    added = "Motion to accept a synthetic report passed; Alex Example voted yes."
    changed = "A revised synthetic denial motion failed; Alex Example voted no."
    refs = [ "6: Revised synthetic matter", "5: Synthetic amendment", "6: Revised synthetic matter" ]
    2.times do |index|
      revision("lost-correspondence-#{index}", [ "Replacement #{index}", added, @excerpts.last, changed ])
      publish(excerpts: [ added, @excerpts.last, changed ], agenda_ref: refs)
      current = observations
      assert_equal [ review.id ], current.last.identity_assignment.conflicting_correction_ids
      assert_equal "identity_correction_conflict", current.last.reason
      assert_nil current.last.identity_assignment.council_decision_id
      assert_nil CouncilDecision.find(first.council_decision_id).current_observation
      assert_equal @original.last.council_decision_id, current[1].identity_assignment.council_decision_id
    end
    replacement_review = resolve(observations.last, decision: first.council_decision, basis: first)
    assert_equal [ review.id ], replacement_review.evidence_manifest["resolved_conflict_ids"]
    assert_equal observations.last.id, CouncilDecision.find(first.council_decision_id).current_observation&.id
  end

  test "review lineage survives an empty publication before decisions return" do
    first = @original.first
    review = resolve(first, decision: first.council_decision, basis: first)
    revision("empty-replacement", [ "No decisions stated in this synthetic replacement." ])
    publish(excerpts: [])
    assert_empty observations
    assert_nil CouncilDecision.find(first.council_decision_id).current_observation
    replacement = "A new synthetic record adopts a different proposal; Alex Example voted yes."
    revision("after-empty", [ replacement ])
    publish(excerpts: [ replacement ])
    assert_equal [ review.id ], observations.first.identity_assignment.conflicting_correction_ids
    assert_nil observations.first.identity_assignment.council_decision_id
    replacement_review = resolve(observations.first, decision: first.council_decision, basis: first)
    assert_equal [ review.id ], replacement_review.evidence_manifest["resolved_conflict_ids"]
  end

  private

  def refresh_votes(data)
    seed_prompt_templates
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| data.to_json }
    Ai::OpenAiService.stub :new, service do
      ExtractVotesJob.perform_now(@meeting.id, refresh: true)
    end
  end

  def prepare_unidentified_meeting
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current, detail_page_url: "https://example.test/unidentified")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.test/unidentified.pdf")
    @agenda = @meeting.agenda_items.create!(number: "5", title: "Synthetic amendment", order_index: 1)
    revision("unidentified", @excerpts)
    publish(agenda_ref: "Unverified item")
  end

  def observations
    @meeting.reload.motions.order(:id).map(&:decision_observation)
  end

  def resolve(observation, action: "assign", decision: nil, basis: nil, actor: @actor,
    reason: "Match the retained opposing motion", expected_correction_id: nil, request_id: SecureRandom.uuid)
    without_ai do
      CouncilDecisions::ResolveIdentity.call(observation: observation, action: action, decision: decision,
        basis_observation: basis, actor: actor, reason: reason, expected_correction_id: expected_correction_id, request_id: request_id)
    end
  end

  def without_ai(&block)
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Identity review and replay must not dispatch providers" }, &block)
  end

  def revision(bytes, pages)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: pages, page_count: pages.size, quality: "text", extractor_version: "synthetic_v1")
  end

  def publish(excerpts: @excerpts, descriptions: excerpts, agenda_ref: "5: Synthetic amendment")
    votes = { motions: excerpts.each_with_index.map { |excerpt, index| { description: descriptions[index], source_excerpt: excerpt,
      agenda_item_ref: agenda_ref.is_a?(Array) ? agenda_ref[index] : agenda_ref, outcome: index.zero? ? "failed" : "passed",
      votes: [ { member: "Alex Example", value: index.zero? ? "no" : "yes" } ] } } }
    attendance = { voting_members_present: [ "Alex Example" ], voting_members_absent: [], non_voting_staff: [], guests: [] }
    service = Object.new
    service.define_singleton_method(:extract_votes) { |*args, **kwargs| votes.to_json }
    service.define_singleton_method(:extract_committee_members) { |*args, **kwargs| attendance.to_json }
    Ai::OpenAiService.stub :new, service do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
  end
end
