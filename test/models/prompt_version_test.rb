require "test_helper"

class PromptVersionTest < ActiveSupport::TestCase
  setup do
    @template = PromptTemplate.create!(
      key: "test_prompt",
      name: "Test Prompt",
      instructions: "Do the thing with {{input}}",
      model_tier: "default"
    )
  end

  test "belongs to prompt_template" do
    version = PromptVersion.create!(
      prompt_template: @template,
      instructions: "Do the thing with {{input}}",
      model_tier: "default",
      editor_note: "Initial"
    )
    assert_equal @template, version.prompt_template
  end

  test "requires instructions" do
    version = PromptVersion.new(prompt_template: @template, model_tier: "default")
    assert_not version.valid?
    assert_includes version.errors[:instructions], "can't be blank"
  end

  test "requires model_tier" do
    version = PromptVersion.new(prompt_template: @template, instructions: "test")
    assert_not version.valid?
    assert_includes version.errors[:model_tier], "can't be blank"
  end

  test "orders by created_at desc" do
    @template.versions.delete_all
    v1 = PromptVersion.create!(prompt_template: @template, instructions: "v1", model_tier: "default", created_at: 2.days.ago)
    v2 = PromptVersion.create!(prompt_template: @template, instructions: "v2", model_tier: "default", created_at: 1.day.ago)

    assert_equal [ v2, v1 ], @template.versions.recent.to_a
  end
end
