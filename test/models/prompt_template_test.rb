require "test_helper"

class PromptTemplateTest < ActiveSupport::TestCase
  test "requires key, name, and instructions" do
    template = PromptTemplate.new
    assert_not template.valid?
    assert_includes template.errors[:key], "can't be blank"
    assert_includes template.errors[:name], "can't be blank"
    assert_includes template.errors[:instructions], "can't be blank"
  end

  test "key must be unique" do
    PromptTemplate.create!(key: "unique_key", name: "Test", instructions: "Do it")
    duplicate = PromptTemplate.new(key: "unique_key", name: "Other", instructions: "Do other")
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:key], "has already been taken"
  end

  test "model_tier defaults to default" do
    template = PromptTemplate.create!(key: "tier_test", name: "Test", instructions: "Do it")
    assert_equal "default", template.model_tier
  end

  test "interpolate replaces placeholders" do
    template = PromptTemplate.new(instructions: "Analyze {{items}} using {{context}}")
    result = template.interpolate(items: "agenda item 1", context: "committee info")
    assert_equal "Analyze agenda item 1 using committee info", result
  end

  test "interpolate raises KeyError for missing required placeholder" do
    template = PromptTemplate.new(instructions: "Analyze {{items}} using {{context}}")
    assert_raises(KeyError) do
      template.interpolate(items: "agenda item 1")
    end
  end

  test "interpolate leaves unmatched placeholders when allow_missing is true" do
    template = PromptTemplate.new(instructions: "Analyze {{items}} using {{context}}")
    result = template.interpolate({ items: "agenda item 1" }, allow_missing: true)
    assert_equal "Analyze agenda item 1 using {{context}}", result
  end

  test "interpolate_system_role replaces placeholders in system_role" do
    template = PromptTemplate.new(system_role: "You are a {{role}} analyst")
    result = template.interpolate_system_role(role: "civic")
    assert_equal "You are a civic analyst", result
  end

  test "creates version on save" do
    template = PromptTemplate.create!(key: "version_test", name: "Test", instructions: "v1", model_tier: "default")
    assert_equal 1, template.versions.count

    version = template.versions.first
    assert_equal "v1", version.instructions
    assert_equal "default", version.model_tier
  end

  test "creates version with editor_note on update" do
    template = PromptTemplate.create!(key: "update_test", name: "Test", instructions: "v1")

    template.update!(instructions: "v2", editor_note: "Changed wording")
    assert_equal 2, template.versions.count

    latest = template.versions.recent.first
    assert_equal "v2", latest.instructions
    assert_equal "Changed wording", latest.editor_note
  end

  test "does not create version if text unchanged" do
    template = PromptTemplate.create!(key: "nochange_test", name: "Test", instructions: "same")
    template.update!(name: "Updated Name")
    assert_equal 1, template.versions.count
  end
end
