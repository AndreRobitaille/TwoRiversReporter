require "test_helper"

class PromptTemplateDataTest < ActiveSupport::TestCase
  test "meeting prompt requires catalog references and honest source locations" do
    prompt = PromptTemplateData::PROMPTS.fetch("analyze_meeting_content")[:instructions]
    assert_includes prompt, "{{source_catalog}}"
    assert_includes prompt, '"kind":"whole_source"'
    assert_includes prompt, '"kind":"pdf_page"'
    assert_includes prompt, "Transcripts have no supported"
    assert_includes prompt, "Minutes and supplementary transcripts are separate sources"
    assert_includes prompt, "A transcript upload does not supersede these official document sources"
    assert_includes prompt, "Do not turn noisy captions into direct quotations"
    assert_includes prompt, '"agenda_item_id": "Integer shared with the corresponding item_details entry, or null if none"'
    refute_includes prompt, '"citation": "Page X"'
    refute_includes prompt, '"citations": ["Page X"]'
  end

  test "committee extraction does not equate Also Present with staff" do
    instructions = PromptTemplateData::PROMPTS.fetch("extract_committee_members").fetch(:instructions)

    assert_includes instructions, '"Also Present" is only a section heading'
    assert_includes instructions, 'Untitled people under "Also Present" are guests'
    assert_includes instructions, "Elected officials attending outside the committee's main roll call are guests"
  end
end
