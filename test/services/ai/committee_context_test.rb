require "test_helper"

class Ai::CommitteeContextTest < ActiveSupport::TestCase
  test "prepare_committee_context includes active committees with descriptions" do
    Committee.create!(name: "City Council", description: "Legislative body", status: "active")
    Committee.create!(name: "Old Board", description: "Gone now", status: "dissolved")
    Committee.create!(name: "Sleeping Board", description: "Resting", status: "dormant")
    Committee.create!(name: "No Description Board", status: "active")

    service = Ai::OpenAiService.new
    context = service.send(:prepare_committee_context)

    assert_includes context, "City Council"
    assert_includes context, "Legislative body"
    assert_includes context, "Sleeping Board"
    assert_includes context, "Resting"
    assert_not_includes context, "Old Board"
    assert_not_includes context, "No Description Board"
  end

  test "prepare_committee_context returns empty string when no committees" do
    service = Ai::OpenAiService.new
    context = service.send(:prepare_committee_context)
    assert_equal "", context
  end

  test "prepare_committee_context includes committee_type" do
    Committee.create!(name: "Main Street Board", description: "Downtown", committee_type: "tax_funded_nonprofit")

    service = Ai::OpenAiService.new
    context = service.send(:prepare_committee_context)

    assert_includes context, "Tax funded nonprofit"
  end
end
