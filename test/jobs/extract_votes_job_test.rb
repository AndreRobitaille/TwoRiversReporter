require "test_helper"
require "minitest/mock"

class ExtractVotesJobTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.ago, status: "parsed",
      detail_page_url: "http://example.com/m/votes-1"
    )
    @minutes_doc = MeetingDocument.create!(
      meeting: @meeting, document_type: "minutes_pdf",
      extracted_text: "Motion to approve lead service line contract. Passed 7-0."
    )
    @item_7a = AgendaItem.create!(
      meeting: @meeting, number: "7a",
      title: "Lead Service Line Replacement Program", order_index: 1
    )
    @item_7b = AgendaItem.create!(
      meeting: @meeting, number: "7b",
      title: "Street Repair Contract", order_index: 2
    )
  end

  test "uses only substantive agenda items and preserves parent context in prompt text" do
    section = AgendaItem.create!(
      meeting: @meeting, number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 0
    )
    child = AgendaItem.create!(
      meeting: @meeting, number: "A.", title: "26-045 Harbor Resolution", parent: section, order_index: 3
    )

    ai_response = { "motions" => [] }.to_json
    captured_kwargs = nil

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **kwargs|
      captured_kwargs = kwargs
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    assert_includes captured_kwargs[:agenda_items_text], "A.: 26-045 Harbor Resolution (ACTION ITEMS)"
    refute_includes captured_kwargs[:agenda_items_text], "7.: ACTION ITEMS"
    mock_ai.verify
  end

  test "links motion to agenda item by item number match" do
    ai_response = {
      "motions" => [ {
        "description" => "Approve lead service line contract",
        "outcome" => "passed",
        "agenda_item_ref" => "7a: Lead Service Line Replacement Program",
        "votes" => [ { "member" => "Ald. Smith", "value" => "yes" } ]
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      kwargs[:agenda_items_text].include?("7a:")
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal @item_7a, motion.agenda_item
    mock_ai.verify
  end

  test "links motion to agenda item when agenda_item_ref is bare number without delimiter" do
    ai_response = {
      "motions" => [ {
        "description" => "Approve lead service line contract",
        "outcome" => "passed",
        "agenda_item_ref" => "7a",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal @item_7a, motion.agenda_item
    mock_ai.verify
  end

  test "links motion to agenda item by title similarity when no number match" do
    item_no_number = AgendaItem.create!(
      meeting: @meeting, number: nil,
      title: "Waterfront Development Proposal", order_index: 3
    )

    ai_response = {
      "motions" => [ {
        "description" => "Approve waterfront development",
        "outcome" => "passed",
        "agenda_item_ref" => "Waterfront Development Proposal",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal item_no_number, motion.agenda_item
    mock_ai.verify
  end

  test "leaves agenda_item nil when ref is null" do
    ai_response = {
      "motions" => [ {
        "description" => "Motion to adjourn",
        "outcome" => "passed",
        "agenda_item_ref" => nil,
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_nil motion.agenda_item_id
    mock_ai.verify
  end

  test "leaves agenda_item nil when ref does not match any item" do
    ai_response = {
      "motions" => [ {
        "description" => "Approve something unknown",
        "outcome" => "passed",
        "agenda_item_ref" => "99z: Nonexistent Item That Cannot Match",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_nil motion.agenda_item_id
    mock_ai.verify
  end

  test "passes agenda items text to AI service" do
    ai_response = { "motions" => [] }.to_json
    captured_kwargs = nil

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      captured_kwargs = kwargs
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    assert_includes captured_kwargs[:agenda_items_text], "7a: Lead Service Line Replacement Program"
    assert_includes captured_kwargs[:agenda_items_text], "7b: Street Repair Contract"
    mock_ai.verify
  end

  test "skips when no minutes text available" do
    @minutes_doc.destroy!

    assert_no_difference "Motion.count" do
      ExtractVotesJob.perform_now(@meeting.id)
    end
  end

  test "enqueues continuity update on missing minutes source" do
    @minutes_doc.destroy!

    assert_enqueued_with(job: Topics::UpdateContinuityJob, args: [ { meeting_id: @meeting.id } ]) do
      ExtractVotesJob.perform_now(@meeting.id)
    end
  end

  test "enqueues continuity update after successful extraction" do
    ai_response = { "motions" => [] }.to_json
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      assert_enqueued_with(job: Topics::UpdateContinuityJob, args: [ { meeting_id: @meeting.id } ]) do
        ExtractVotesJob.perform_now(@meeting.id)
      end
    end
  end

  test "links motions to substantive child agenda items instead of parent sections" do
    # Simulates the real production case: a council work session agenda with a
    # "7. ACTION ITEMS" section header and a sub-item "A. 26-045 Harbor Resolution"
    # under it. AI may return a multi-line ref with both the parent and the child.
    # The resolver should pick the specific sub-item, not the section header.
    section_header = AgendaItem.create!(
      meeting: @meeting, number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 10
    )
    sub_item = AgendaItem.create!(
      meeting: @meeting, number: "A.",
      title: "26-045 Resolution Adopting Three-Year Harbor Development Statement of Intentions for 2027-2029",
      kind: "item",
      parent: section_header,
      order_index: 11
    )

    ai_response = {
      "motions" => [ {
        "description" => "Motion to waive reading and adopt Resolution 26-045",
        "outcome" => "passed",
        "agenda_item_ref" => "7.: ACTION ITEMS\nA.: 26-045 Resolution Adopting Three-Year Harbor Development Statement of Intentions for 2027-2029",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal sub_item, motion.agenda_item,
                  "Expected resolver to pick specific sub-item, not the ACTION ITEMS section header"
    refute_equal section_header, motion.agenda_item
    mock_ai.verify
  end

  test "links motion to child item when parent section is only prompt context" do
    section_header = AgendaItem.create!(
      meeting: @meeting, number: "8.", title: "NEW BUSINESS", kind: "section", order_index: 12
    )
    sub_item = AgendaItem.create!(
      meeting: @meeting,
      number: "B.",
      title: "Storm Water Grant Resolution",
      kind: "item",
      parent: section_header,
      order_index: 13
    )

    ai_response = {
      "motions" => [ {
        "description" => "Approve the storm water grant resolution",
        "outcome" => "passed",
        "agenda_item_ref" => "B.: Storm Water Grant Resolution",
        "votes" => []
      } ]
    }.to_json

    captured_kwargs = nil
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **kwargs|
      captured_kwargs = kwargs
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal sub_item, motion.agenda_item
    assert_includes captured_kwargs[:agenda_items_text], "B.: Storm Water Grant Resolution (NEW BUSINESS)"
    refute_includes captured_kwargs[:agenda_items_text], "8.: NEW BUSINESS"
    mock_ai.verify
  end

  test "vote extraction still links to upgraded legacy child item after rerun" do
    section = AgendaItem.create!(meeting: @meeting, number: "8.", title: "NEW BUSINESS", kind: "section", order_index: 10)
    child = AgendaItem.create!(meeting: @meeting, number: "B.", title: "Storm Water Grant Resolution", kind: nil, parent: nil, order_index: 11)
    @meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "8. NEW BUSINESS B. Storm Water Grant Resolution")

    Scrapers::ParseAgendaJob.perform_now(@meeting.id)

    child.reload
    assert_equal "item", child.kind
    assert_equal section.id, child.parent_id

    ai_response = {
      "motions" => [ {
        "description" => "Approve the storm water grant resolution",
        "outcome" => "passed",
        "agenda_item_ref" => "B.: Storm Water Grant Resolution",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **_kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    assert_equal child.id, @meeting.motions.reload.first.agenda_item_id
    mock_ai.verify
  end

  test "uses parent section context to disambiguate duplicate child titles" do
    new_business = AgendaItem.create!(meeting: @meeting, number: "8.", title: "NEW BUSINESS", kind: "section", order_index: 12)
    consent = AgendaItem.create!(meeting: @meeting, number: "9.", title: "CONSENT AGENDA", kind: "section", order_index: 13)
    target_item = AgendaItem.create!(meeting: @meeting, number: "A.", title: "Resolution", kind: "item", parent: new_business, order_index: 14)
    other_item = AgendaItem.create!(meeting: @meeting, number: "A.", title: "Resolution", kind: "item", parent: consent, order_index: 15)

    ai_response = {
      "motions" => [ {
        "description" => "Approve the new business resolution",
        "outcome" => "passed",
        "agenda_item_ref" => "A.: Resolution (NEW BUSINESS)",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **_kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    assert_equal target_item, @meeting.motions.reload.first.agenda_item
    refute_equal other_item, @meeting.motions.reload.first.agenda_item
    mock_ai.verify
  end

  test "is idempotent — clears and rebuilds motions" do
    Motion.create!(meeting: @meeting, description: "Old motion", outcome: "passed")

    ai_response = {
      "motions" => [ {
        "description" => "New motion",
        "outcome" => "passed",
        "agenda_item_ref" => nil,
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |text, **kwargs|
      true
    end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motions = @meeting.motions.reload
    assert_equal 1, motions.size
    assert_equal "New motion", motions.first.description
    mock_ai.verify
  end

  test "records votes extraction status and timestamp on success" do
    ai_response = {
      "motions" => [ {
        "description" => "Approve lead service line contract",
        "outcome" => "passed",
        "agenda_item_ref" => "7a",
        "votes" => []
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    state = @meeting.reload.processing_state
    assert_equal "processed", state["votes_extraction_status"]
    assert_not_nil state["votes_extracted_at"]
  end

  test "retries missing_source once minutes text becomes available" do
    @minutes_doc.update!(extracted_text: nil)

    ExtractVotesJob.perform_now(@meeting.id)
    assert_equal "missing_source", @meeting.reload.processing_state["votes_extraction_status"]

    @minutes_doc.update!(extracted_text: "Motion to approve lead service line contract. Passed 7-0.")
    ai_response = { "motions" => [ { "description" => "Approve lead service line contract", "outcome" => "passed", "agenda_item_ref" => "7a", "votes" => [] } ] }.to_json
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    assert_equal "processed", @meeting.reload.processing_state["votes_extraction_status"]
    mock_ai.verify
  end

  test "records votes extraction empty when no motions are returned" do
    ai_response = { "motions" => [] }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    state = @meeting.reload.processing_state
    assert_equal "empty", state["votes_extraction_status"]
    assert_not_nil state["votes_extracted_at"]
  end

  test "records votes extraction parse_error when AI returns invalid json" do
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, "not-json" do |_text, **kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    state = @meeting.reload.processing_state
    assert_equal "parse_error", state["votes_extraction_status"]
    assert_not_nil state["votes_extracted_at"]
  end

  test "drops unseconded motions instead of treating later roll call as their outcome" do
    @minutes_doc.update!(extracted_text: <<~TEXT)
      A. 26-095 Resolution Authorizing Application for DNR Stewardship Recreational Boating Grant
      Recommended Action: Motion to waive reading and authorize the resolution
      Motion made by Dahlke to table, no second motion. Motion carried with roll call vote.
      Motion made by Derby, seconded by B. LeClair.
      Voting Yea: Brandt, Petri, Stechmesser, D. LeClair, Bittner, Derby, B. LeClair
      Voting Nay: Dahlke
    TEXT
    item = AgendaItem.create!(
      meeting: @meeting,
      number: "A.",
      title: "26-095 Resolution Authorizing Application for DNR Stewardship Recreational Boating Grant",
      order_index: 3
    )

    ai_response = {
      "motions" => [
        {
          "description" => "Motion to table.",
          "outcome" => "tabled",
          "agenda_item_ref" => "A.: 26-095 Resolution Authorizing Application for DNR Stewardship Recreational Boating Grant",
          "votes" => [ { "member" => "Doug Brandt", "value" => "yes" } ]
        },
        {
          "description" => "Motion to waive reading and authorize the resolution.",
          "outcome" => "passed",
          "agenda_item_ref" => "A.: 26-095 Resolution Authorizing Application for DNR Stewardship Recreational Boating Grant",
          "votes" => [ { "member" => "Doug Brandt", "value" => "yes" } ]
        }
      ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **_kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motions = @meeting.motions.reload
    assert_equal 1, motions.size
    assert_equal "passed", motions.first.outcome
    assert_equal item, motions.first.agenda_item
    assert_includes motions.first.description, "authorize the resolution"
    mock_ai.verify
  end

  test "adds absent voting members to extracted roll call votes when AI omits them" do
    absent_member = Member.create!(name: "Adam Wachowski")
    MeetingAttendance.create!(
      meeting: @meeting,
      member: absent_member,
      status: "absent",
      attendee_type: "voting_member"
    )

    ai_response = {
      "motions" => [ {
        "description" => "Approve lead service line contract",
        "outcome" => "passed",
        "agenda_item_ref" => "7a: Lead Service Line Replacement Program",
        "votes" => [ { "member" => "Ald. Smith", "value" => "yes" } ]
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_votes, ai_response do |_text, **_kwargs| true end

    Ai::OpenAiService.stub :new, mock_ai do
      ExtractVotesJob.perform_now(@meeting.id)
    end

    motion = @meeting.motions.reload.first
    assert_equal "absent", motion.votes.find_by!(member: absent_member).value
    mock_ai.verify
  end

  test "records votes extraction missing_source when minutes are absent" do
    @minutes_doc.destroy!

    ExtractVotesJob.perform_now(@meeting.id)

    state = @meeting.reload.processing_state
    assert_equal "missing_source", state["votes_extraction_status"]
    assert_not_nil state["votes_extracted_at"]
  end
end
