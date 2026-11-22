require "test_helper"
require "minitest/mock"

class Ai::MinutesInputTest < ActiveSupport::TestCase
  test "both minutes methods preserve the full allowed input through provider messages and prompt receipt" do
    seed_prompt_templates
    source = "x " * 24_980 + "UNIQUE FINAL ACTION"
    assert_operator source.length, :<=, Ai::OpenAiService::MAX_MINUTES_CHARS
    service = Ai::OpenAiService.new
    %i[extract_votes extract_committee_members].each do |method|
      captured = nil
      response = ->(**kwargs) { captured = kwargs.fetch(:messages); [ "{}", 1 ] }
      service.stub :call_api, response do
        service.public_send(method, source)
      end
      assert_includes captured.last.fetch(:content), source
      run = PromptRun.order(:id).last
      assert_equal source, run.placeholder_values.fetch("text")
    end
  end

  test "a pinned template is used even after its database row changes" do
    seed_prompt_templates
    template = PromptTemplate.find_by!(key: "extract_votes")
    template.update!(instructions: "ORIGINAL instructions {{text}} {{agenda_items}}")
    pinned = PromptTemplate.find(template.id)
    template.update!(instructions: "NEW instructions {{text}} {{agenda_items}}")
    messages = nil
    service = Ai::OpenAiService.new
    service.stub :call_api, ->(**kwargs) { messages = kwargs.fetch(:messages); [ "{}", 1 ] } do
      service.extract_votes("Known final action", template: pinned)
    end
    assert_includes messages.last.fetch(:content), "ORIGINAL instructions Known final action"
    assert_not_includes messages.last.fetch(:content), "NEW instructions"
  end

  test "both minutes methods reject oversized input before provider transport" do
    service = Ai::OpenAiService.new
    service.stub :call_api, ->(*) { flunk "Oversized minutes reached provider" } do
      %i[extract_votes extract_committee_members].each do |method|
        assert_raises(Ai::OpenAiService::InputTooLargeError) do
          service.public_send(method, "x" * (Ai::OpenAiService::MAX_MINUTES_CHARS + 1))
        end
      end
    end
  end
end
