require "test_helper"

class MeetingAnalysisEvidenceValidatorTest < ActiveSupport::TestCase
  test "preserves an announced decision while rejecting an invented voice-vote tally and unnamed mover" do
    source = "I'll make the motion. Second. Thank you, Bill. All in favor? Aye. Anyone opposed? Motion carried."
    item = {
      "decision" => "Passed", "vote" => "9-0", "vote_evidence" => source,
      "motion" => { "mover" => "Tim Petri", "seconder" => "Bill LeClair", "no_votes" => [] },
      "motion_evidence" => { "mover" => source, "seconder" => "Second. Thank you, Bill." }
    }

    result = validate(item, source)
    assert_equal "Passed", result["decision"]
    assert_nil result["vote"]
    assert_nil result.dig("motion", "mover")
    assert_equal "Bill LeClair", result.dig("motion", "seconder")
  end

  test "retains a clear roll-call tally without assigning the anonymous no vote" do
    source = "Roll call vote. Mark Bittner. Aye. Doug Brandt. Aye. No. Motion carries."
    item = { "vote" => "2-1", "vote_evidence" => source,
      "motion" => { "no_votes" => [ "Adam Wachowski" ] },
      "motion_evidence" => { "no_votes" => [ source ] } }

    result = validate(item, source)
    assert_equal "2-1", result["vote"]
    assert_nil result.dig("motion", "no_votes")
  end

  test "retains individual vote counts when captions omit the roll-call introduction" do
    source = "Mark Bittner. Aye. Doug Brandt. Aye. No. Motion carries."
    item = { "vote" => "2-1", "vote_evidence" => source.upcase }

    assert_equal "2-1", validate(item, source)["vote"]
  end

  test "tolerates caption name spelling and quote punctuation without changing vote responses" do
    source = "bill leclair aye doug brandt Aye. Katherine Dahlke. No. Motion carries."
    roster = "Canonical roster: Bill LeClair, Doug Brandt, Katherine Dahlke."
    item = { "vote" => "2-1", "vote_evidence" =>
      "Bill Leclair. Aye. Doug Brand. Aye. Katherine Dahlke. No. Motion carries." }
    assert_equal "2-1", validate(item, source, participant_context: roster)["vote"]

    item["vote"] = "3-0"
    item["vote_evidence"] = item["vote_evidence"].sub("No.", "Aye.")
    assert_nil validate(item, source, participant_context: roster)["vote"]
  end

  test "preserves operator-verified motion facts separately from the noisy transcript" do
    review = "Mark Bittner moved. Doug Brandt seconded. The motion passed 6-2. " \
      "Katherine Dahlke and Adam Wachowski voted no. Scott Stechmesser was absent."
    item = { "vote" => "6-2", "vote_evidence" => "The motion passed 6-2.",
      "motion" => { "mover" => "Mark Bittner", "seconder" => "Doug Brandt",
        "no_votes" => [ "Katherine Dahlke", "Adam Wachowski" ], "absent_members" => [ "Scott Stechmesser" ] },
      "motion_evidence" => { "mover" => "Mark Bittner moved.", "seconder" => "Doug Brandt seconded.",
        "no_votes" => Array.new(2, "Katherine Dahlke and Adam Wachowski voted no."),
        "absent_members" => [ "Scott Stechmesser was absent." ] } }

    result = validate(item, "Garbled roll call.", motion_context: review)
    assert_equal "6-2", result["vote"]
    assert_equal item["motion"], result["motion"]
  end

  test "rejects nonexistent source quotes and evidence from another person's motion" do
    source = "Mark Bittner moved approval. The motion passed 6-2."
    item = { "vote" => "6-2", "vote_evidence" => "The motion passed 6-2 unanimously.",
      "motion" => { "mover" => "Tim Petri" }, "motion_evidence" => { "mover" => source } }

    result = validate(item, source)
    assert_nil result["vote"]
    assert_nil result.dig("motion", "mover")
  end

  test "does not treat earlier discussion as evidence of a motion role" do
    source = "Tim Petri discussed parking. I'll make the motion."
    item = { "motion" => { "mover" => "Tim Petri" },
      "motion_evidence" => { "mover" => "Tim Petri discussed parking." } }

    assert_nil validate(item, source).dig("motion", "mover")
  end

  test "does not mistake an addressed mover for the anonymous seconder" do
    source = "I'll second Mark."
    item = { "motion" => { "seconder" => "Mark Bittner" },
      "motion_evidence" => { "seconder" => source } }

    assert_nil validate(item, source).dig("motion", "seconder")
  end

  test "does not identify a different participant who shares a surname" do
    source = "Bill LeClair made the motion."
    item = { "motion" => { "mover" => "Darla LeClair" }, "motion_evidence" => { "mover" => source } }
    roster = "Canonical roster: Bill LeClair, Darla LeClair."

    assert_nil validate(item, source, participant_context: roster).dig("motion", "mover")
    item["motion"]["mover"] = "Bill LeClair"
    assert_equal "Bill LeClair", validate(item, source, participant_context: roster).dig("motion", "mover")
  end

  test "requires evidence for every named dissenter and preserves known empty no votes" do
    source = "The motion passed 6-2. Katherine Dahlke and Adam Wachowski voted no."
    item = { "vote" => "6-2", "vote_evidence" => "The motion passed 6-2.",
      "motion" => { "no_votes" => [ "Katherine Dahlke", "Adam Wachowski" ] },
      "motion_evidence" => { "no_votes" => [ "Katherine Dahlke and Adam Wachowski voted no." ] } }
    assert_nil validate(item, source).dig("motion", "no_votes")

    item["motion"]["no_votes"] = []
    assert_nil validate(item, source).dig("motion", "no_votes")

    item["vote"] = "9-0"
    item["vote_evidence"] = "The motion passed 9-0."
    assert_equal [], validate(item, "The motion passed 9-0.").dig("motion", "no_votes")
  end

  private

  def validate(item, source, motion_context: nil, participant_context: nil)
    content = { "item_details" => [ item ] }.to_json
    result = Ai::MeetingAnalysisEvidenceValidator.new(document_text: source, motion_context: motion_context,
      participant_context: participant_context).validate(content)
    JSON.parse(result)["item_details"].first
  end
end
