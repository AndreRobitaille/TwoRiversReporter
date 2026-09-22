require "test_helper"
require "rake"
require "digest"

class PromptTemplatesRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("prompt_templates:populate")
    Rake::Task["prompt_templates:populate"].reenable
    Rake::Task["prompt_templates:sync_selected"].reenable
  end

  test "populate refreshes existing placeholders metadata" do
    template = PromptTemplate.find_or_create_by!(key: "extract_votes") do |t|
      t.name = "Vote Extraction"
      t.description = "Extracts motions and vote records from meeting minutes"
      t.model_tier = "default"
      t.placeholders = [ { "name" => "stale", "description" => "stale" } ]
      t.system_role = "Old role"
      t.instructions = "Old instructions"
    end

    template.update!(placeholders: [ { "name" => "stale", "description" => "stale" } ])

    Rake::Task["prompt_templates:populate"].invoke

    assert_equal PromptTemplateData::METADATA.find { |meta| meta[:key] == "extract_votes" }[:placeholders], template.reload.placeholders
  ensure
    Rake::Task["prompt_templates:populate"].reenable
  end

  test "populate creates missing templates from PromptTemplateData" do
    PromptTemplate.where(key: "generated_image_brief").destroy_all

    assert_difference -> { PromptTemplate.where(key: "generated_image_brief").count }, 1 do
      Rake::Task["prompt_templates:populate"].invoke
    end

    template = PromptTemplate.find_by!(key: "generated_image_brief")
    assert_equal "Generated Image Brief", template.name
    assert_equal PromptTemplateData::PROMPTS["generated_image_brief"][:instructions].strip, template.instructions
  ensure
    Rake::Task["prompt_templates:populate"].reenable
  end

  test "validate exits nonzero when templates are missing" do
    PromptTemplate.where(key: "generated_image_brief").destroy_all

    out, err = capture_io do
      assert_raises(SystemExit) do
        Rake::Task["prompt_templates:validate"].invoke
      end
    end

    assert_match(/MISSING templates/, out + err)
  ensure
    Rake::Task["prompt_templates:validate"].reenable
  end

  test "validate is driven by Ai::OpenAiService required prompt keys" do
    rake_source = File.read(Rails.root.join("lib/tasks/prompt_templates.rake"))
    assert_includes rake_source, "Ai::OpenAiService::REQUIRED_PROMPT_KEYS"
  end

  test "sync_selected is a dry run unless apply is explicit" do
    template = ensure_prompt_template("analyze_topic_summary")
    template.update!(instructions: "Locally edited prompt")

    with_env("KEYS" => template.key, "APPLY" => nil, "EXPECTED_SHA256S" => nil) do
      output, = capture_io { Rake::Task["prompt_templates:sync_selected"].invoke }
      assert_match(/Dry run only/, output)
    end

    assert_equal "Locally edited prompt", template.reload.instructions
  ensure
    Rake::Task["prompt_templates:sync_selected"].reenable
  end

  test "sync_selected refuses an unexpected edited production prompt" do
    template = ensure_prompt_template("analyze_topic_summary")
    template.update!(instructions: "Editorial production edit")

    with_env("KEYS" => template.key, "APPLY" => "true", "EXPECTED_SHA256S" => "#{template.key}=wrong") do
      assert_raises(SystemExit) { Rake::Task["prompt_templates:sync_selected"].invoke }
    end

    assert_equal "Editorial production edit", template.reload.instructions
  ensure
    Rake::Task["prompt_templates:sync_selected"].reenable
  end

  test "sync_selected applies an explicitly fingerprinted prompt and preserves a version" do
    template = ensure_prompt_template("analyze_topic_summary")
    template.update!(instructions: "Known prior prompt")
    fingerprint = prompt_fingerprint(template)

    with_env(
      "KEYS" => template.key,
      "APPLY" => "true",
      "EXPECTED_SHA256S" => "#{template.key}=#{fingerprint}"
    ) do
      assert_difference -> { template.versions.count }, 1 do
        capture_io { Rake::Task["prompt_templates:sync_selected"].invoke }
      end
    end

    assert_equal PromptTemplateData::PROMPTS.fetch(template.key).fetch(:instructions), template.reload.instructions
  ensure
    Rake::Task["prompt_templates:sync_selected"].reenable
  end

  private

  def ensure_prompt_template(key)
    meta = PromptTemplateData::METADATA.find { |entry| entry[:key] == key }
    data = PromptTemplateData::PROMPTS.fetch(key)
    PromptTemplate.find_or_create_by!(key: key) do |template|
      template.name = meta.fetch(:name)
      template.description = meta.fetch(:description)
      template.model_tier = meta.fetch(:model_tier)
      template.system_role = data[:system_role]
      template.instructions = data.fetch(:instructions)
    end
  end

  def prompt_fingerprint(template)
    Digest::SHA256.hexdigest(JSON.generate({
      system_role: template.system_role.presence,
      instructions: template.instructions.to_s.strip,
      model_tier: template.model_tier
    }))
  end

  def with_env(values)
    original = values.to_h { |key, _value| [ key, ENV[key] ] }
    values.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    yield
  ensure
    original.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end
end
