require "test_helper"
require "minitest/mock"
require_relative "../support/council_issue_scenario"

class CouncilSourceQuoteFootersTest < ActionDispatch::IntegrationTest
  include CouncilIssueScenario

  setup do
    setup_issue_updates
    first, second = @quote.split("requires ", 2)
    @page_one = @document.extractions.create!(page_number: 1, raw_text: "#{first}requires\n\n1\n",
      cleaned_text: "#{first}requires 1")
    @page_two = @document.extractions.create!(page_number: 2, raw_text: "#{second}\n#{@completion}\n\n2\n",
      cleaned_text: "#{second} #{@completion} 2")
    @document.update!(page_count: 2, extracted_text: "#{@page_one.cleaned_text} #{@page_two.cleaned_text}")
  end

  test "a verified omitted page footer restores the exact retained passage and shared profiles" do
    stage = extract_issue_updates
    assert_equal "completed", stage.status
    restored = stage.data.fetch("updates").first.fetch("quote")
    assert_equal @quote.sub("requires ", "requires 1 "), restored
    assert_includes @document.extracted_text, restored
    assert_equal @quote, JSON.parse(stage.requests.sole.response_body).fetch("updates").first.fetch("quote")
    [ @member, @peer ].each do |member|
      get member_path(member)
      assert_response :success
      assert_select "#issue-updates [data-issue-update]", count: 2
      assert_select "#issue-updates blockquote", text: restored
    end
    assert_equal 1, @calls.size
  end

  test "a retained rejected response recovers without spending or changing the receipt" do
    strict = Object.new
    text = @document.extracted_text
    strict.define_singleton_method(:resolve) { |quote| quote if text.include?(quote) }
    stage = nil
    CouncilProfiles::SourceQuote.stub(:new, strict) { stage = extract_issue_updates }
    assert_equal "failed", stage.status
    assert_equal CouncilProfiles::IssueUpdates::InvalidResponse.name, stage.error_code
    receipt = stage.requests.sole.attributes
    get member_path(@member)
    assert_select "#issue-updates", count: 0
    Ai::OpenAiService.stub(:new, ->(*) { flunk "Rechecking saved output must not construct a provider" }) do
      assert_no_difference [ "CouncilIssueRequest.count", "CouncilAiReservation.count", "Vote.count" ] do
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
        ExtractCouncilIssueUpdatesJob.perform_now(@document.id)
      end
    end
    assert_equal "completed", stage.reload.status
    assert_nil stage.error_code
    assert_equal 1, stage.attempts
    assert_equal receipt, stage.requests.sole.reload.attributes
    get member_path(@member)
    assert_select "#issue-updates [data-issue-update]", count: 2
  end

  test "numeric content within a page cannot be omitted as if it were a footer" do
    context = CouncilProfiles::IssueInput.new(@document).context
    locator = CouncilProfiles::SourceQuote.new(context, document: @document)
    assert locator.resolve(@quote)
    assert_nil locator.resolve(@quote.sub("$100,000", ""))
    @page_one.update!(raw_text: @page_one.raw_text.sub("\n\n1\n", " 1\n"))
    assert_nil CouncilProfiles::SourceQuote.new(context, document: @document).resolve(@quote)
  end

  test "changed incomplete or unverified page text cannot repair a quotation" do
    context = CouncilProfiles::IssueInput.new(@document).context
    assert CouncilProfiles::SourceQuote.new(context, document: @document).resolve(@quote)
    @page_one.update!(cleaned_text: @page_one.cleaned_text.sub("$100,000", "$200,000"))
    assert_nil CouncilProfiles::SourceQuote.new(context, document: @document).resolve(@quote)
    @page_one.reload.destroy!
    assert_nil CouncilProfiles::SourceQuote.new(context, document: @document).resolve(@quote)
    assert_nil CouncilProfiles::SourceQuote.new(context).resolve(@quote)
  end
end
