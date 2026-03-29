require "test_helper"

class PromptRunTest < ActiveSupport::TestCase
  test "creates a prompt run with valid attributes" do
    run = PromptRun.create!(
      prompt_template_key: "extract_votes",
      ai_model: "gpt-5.2",
      messages: [
        { "role" => "system", "content" => "You are a vote extractor" },
        { "role" => "user", "content" => "Extract votes from: ..." }
      ],
      response_body: '{"motions": []}',
      response_format: "json_object",
      temperature: 0.1,
      duration_ms: 1500,
      placeholder_values: { "text" => "some meeting text" }
    )

    assert run.persisted?
    assert_equal "extract_votes", run.prompt_template_key
    assert_equal 2, run.messages.size
  end

  test "requires prompt_template_key" do
    run = PromptRun.new(ai_model: "gpt-5.2", messages: [], response_body: "x")
    assert_not run.valid?
    assert_includes run.errors[:prompt_template_key], "can't be blank"
  end

  test "requires ai_model" do
    run = PromptRun.new(prompt_template_key: "x", messages: [], response_body: "x")
    assert_not run.valid?
    assert_includes run.errors[:ai_model], "can't be blank"
  end

  test "requires response_body" do
    run = PromptRun.new(prompt_template_key: "x", ai_model: "gpt-5.2", messages: [])
    assert_not run.valid?
    assert_includes run.errors[:response_body], "can't be blank"
  end

  test "polymorphic source association" do
    meeting = meetings(:one) rescue nil
    skip "No meeting fixture available" unless meeting

    run = PromptRun.create!(
      prompt_template_key: "analyze_meeting_content",
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "test" } ],
      response_body: "{}",
      source: meeting
    )

    assert_equal "Meeting", run.source_type
    assert_equal meeting.id, run.source_id
  end

  test "prunes old runs keeping most recent 10 per key" do
    12.times do |i|
      PromptRun.create!(
        prompt_template_key: "extract_votes",
        ai_model: "gpt-5.2",
        messages: [ { "role" => "user", "content" => "run #{i}" } ],
        response_body: "result #{i}"
      )
    end

    assert_equal 10, PromptRun.where(prompt_template_key: "extract_votes").count
  end

  test "pruning does not affect other template keys" do
    12.times do |i|
      PromptRun.create!(
        prompt_template_key: "extract_votes",
        ai_model: "gpt-5.2",
        messages: [ { "role" => "user", "content" => "run #{i}" } ],
        response_body: "result #{i}"
      )
    end

    other = PromptRun.create!(
      prompt_template_key: "extract_topics",
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "other" } ],
      response_body: "other result"
    )

    assert other.persisted?
    assert_equal 1, PromptRun.where(prompt_template_key: "extract_topics").count
  end

  test "recent scope orders by created_at desc" do
    old = PromptRun.create!(
      prompt_template_key: "extract_votes",
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "old" } ],
      response_body: "old",
      created_at: 2.hours.ago
    )
    new_run = PromptRun.create!(
      prompt_template_key: "extract_votes",
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "new" } ],
      response_body: "new"
    )

    assert_equal new_run, PromptRun.where(prompt_template_key: "extract_votes").recent.first
  end

  test "for_template scope filters by key" do
    PromptRun.create!(
      prompt_template_key: "extract_votes",
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "a" } ],
      response_body: "a"
    )
    PromptRun.create!(
      prompt_template_key: "extract_topics",
      ai_model: "gpt-5.2",
      messages: [ { "role" => "user", "content" => "b" } ],
      response_body: "b"
    )

    assert_equal 1, PromptRun.for_template("extract_votes").count
  end
end
