require "test_helper"

class Ai::OpenAiServicePromptTemplateTest < ActiveSupport::TestCase
  test "PromptTemplate.interpolate replaces all placeholders" do
    template = PromptTemplate.new(
      instructions: "Extract votes from:\n{{text}}\nReturn json."
    )
    result = template.interpolate(text: "The motion passed 5-2.")
    assert_equal "Extract votes from:\nThe motion passed 5-2.\nReturn json.", result
  end

  test "PromptTemplate.interpolate_system_role works for system messages" do
    template = PromptTemplate.new(
      system_role: "You are a {{role}} for {{city}}."
    )
    result = template.interpolate_system_role(role: "civic journalist", city: "Two Rivers, WI")
    assert_equal "You are a civic journalist for Two Rivers, WI.", result
  end

  test "find_by! raises for missing key" do
    assert_raises(ActiveRecord::RecordNotFound) do
      PromptTemplate.find_by!(key: "nonexistent_key")
    end
  end

  test "PromptTemplate.interpolate raises on missing placeholder" do
    template = PromptTemplate.new(
      instructions: "Hello {{name}}, welcome to {{city}}."
    )
    assert_raises(KeyError) do
      template.interpolate(name: "Andre")
    end
  end

  test "PromptTemplate.interpolate with allow_missing preserves unmatched placeholders" do
    template = PromptTemplate.new(
      instructions: "Hello {{name}}, welcome to {{city}}."
    )
    result = template.interpolate({ name: "Andre" }, allow_missing: true)
    assert_equal "Hello Andre, welcome to {{city}}.", result
  end

  test "interpolate_system_role returns empty string when system_role is nil" do
    template = PromptTemplate.new(system_role: nil)
    result = template.interpolate_system_role(foo: "bar")
    assert_equal "", result
  end
end
