require "test_helper"

class PromptTemplateDataTest < ActiveSupport::TestCase
  test "committee extraction does not equate Also Present with staff" do
    instructions = PromptTemplateData::PROMPTS.fetch("extract_committee_members").fetch(:instructions)

    assert_includes instructions, '"Also Present" is only a section heading'
    assert_includes instructions, 'Untitled people under "Also Present" are guests'
    assert_includes instructions, "Elected officials attending outside the committee's main roll call are guests"
  end
end
