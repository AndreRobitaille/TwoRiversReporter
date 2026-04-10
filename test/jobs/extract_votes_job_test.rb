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
end
