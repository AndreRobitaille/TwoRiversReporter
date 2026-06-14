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

  test "PromptTemplateData includes every service-required key" do
    required_keys = Ai::OpenAiService::REQUIRED_PROMPT_KEYS
    assert_empty required_keys - PromptTemplateData::METADATA.map { |meta| meta[:key] }
  end

  test "generated_image_brief usage_context is present" do
    meta = PromptTemplateData::METADATA.find { |item| item[:key] == "generated_image_brief" }
    assert_predicate meta[:usage_context], :present?
  end

  test "generated_image_brief asks for fair weather daylight without forcing sunshine" do
    instructions = PromptTemplateData::PROMPTS.fetch("generated_image_brief").fetch(:instructions)

    assert_includes instructions, "ordinary fair-weather daylight"
    assert_includes instructions, "clear, lightly cloudy, or partly sunny"
    assert_includes instructions, "grounded civic-news tone"
    assert_no_match(/always sunny/i, instructions)
  end

  test "seed_prompt_templates repairs missing keys even when count is high" do
    PromptTemplate.where(key: [ "filler_1", "filler_2" ]).destroy_all
    PromptTemplate.create!(key: "filler_1", name: "Filler 1", instructions: "x")
    PromptTemplate.create!(key: "filler_2", name: "Filler 2", instructions: "x")
    PromptTemplateData::METADATA.first(5).each do |meta|
      next if PromptTemplate.exists?(key: meta[:key])

      PromptTemplate.create!(
        key: meta[:key],
        name: meta[:name],
        instructions: PromptTemplateData::PROMPTS[meta[:key]][:instructions],
        model_tier: meta[:model_tier],
        system_role: PromptTemplateData::PROMPTS[meta[:key]][:system_role]
      )
    end

    seed_prompt_templates

    assert PromptTemplate.exists?(key: "generated_image_brief")
    assert PromptTemplate.exists?(key: "extract_knowledge")
  end
end
