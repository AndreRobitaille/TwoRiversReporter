require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesRequestReceiptsTest < ActiveJob::TestCase
  setup do
    seed_prompt_templates
    @meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: Time.current,
      detail_page_url: "https://example.test/request-receipts")
    @document = @meeting.meeting_documents.create!(document_type: "minutes_pdf",
      source_url: "https://example.test/request-receipts.pdf")
    URI.stub(:open, ->(*) { StringIO.new("synthetic request evidence") }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: [ "Alex Request voted no. Blair Request voted yes. FINAL REQUEST ACTION." ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v1")
    @calls = []
    clear_enqueued_jobs
  end

  test "real jobs bound provider output and retain shared stage receipts through publication and unchanged replay" do
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    assert_equal 2, @calls.size
    assert_equal [ 4_000, 4_000 ], @calls.map { |params| params[:max_completion_tokens] }
    assert @calls.all? { |params| params[:messages].last[:content].include?("FINAL REQUEST ACTION") }
    assert_equal [ "First request action", "Final request action" ], @meeting.motions.order(:id).pluck(:description)
    fresh = Meeting.find(@meeting.id)
    assert_equal [ [ "Alex Request", "no" ], [ "Blair Request", "yes" ] ],
      fresh.motions.order(:id).last.votes.joins(:member).order("members.name").pluck("members.name", :value)
    assert_equal [ "Alex Request", "Blair Request" ],
      fresh.meeting_attendances.joins(:member).order("members.name").pluck("members.name")
    receipts = MinutesRequest.order(:id).to_a
    assert_equal 2, receipts.size
    assert_equal %w[received received], receipts.map(&:status)
    assert_equal %w[attendance votes], receipts.map { |receipt| receipt.minutes_extraction.kind }.sort
    receipts.each do |receipt|
      assert_equal 1, receipt.attempt
      assert_equal 4_000, receipt.request_parameters.fetch("max_completion_tokens")
      assert_equal 31, receipt.usage.fetch("input_tokens")
      assert_equal 11, receipt.usage.fetch("cached_input_tokens")
      assert_equal 17, receipt.usage.fetch("output_tokens")
      assert_equal 5, receipt.usage.fetch("reasoning_tokens")
      assert_equal "stop", receipt.finish_reason
      assert_equal "synthetic-response", receipt.provider_response_id
      assert_equal "synthetic-resolved-model", receipt.response_model
      assert_includes receipt.messages.last.fetch("content"), "FINAL REQUEST ACTION"
      assert_equal receipt.minutes_extraction.data, JSON.parse(receipt.response_body)
    end
    ids = @meeting.motions.order(:id).pluck(:id)
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
      Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    end
    assert_equal 2, @calls.size
    assert_equal receipts.map(&:id), MinutesRequest.order(:id).pluck(:id)
    assert_equal ids, Meeting.find(@meeting.id).motions.order(:id).pluck(:id)
    assert_no_enqueued_jobs only: ExtractVotesJob
    assert_no_enqueued_jobs only: ExtractCommitteeMembersJob
  end

  test "a valid-looking length-limited response is retained but never published or automatically retried" do
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
    prior = @meeting.reload.minutes_publication
    Documents::PublishText.new(@document.reload).call(raw_pages: [ "Changed final source action." ],
      page_count: 1, quality: "text", extractor_version: "synthetic_v2")
    limited = ->(params) { provider_response(params).tap { |response| response["choices"][0]["finish_reason"] = "length" } }
    with_transport(response: limited) { 3.times { ExtractVotesJob.perform_now(@meeting.id) } }
    stage = @meeting.minutes_extractions.where(kind: "votes").order(:id).last
    assert_equal 3, @calls.size
    assert_equal "incomplete", stage.status
    assert_equal "length", stage.error_code
    assert_equal 1, stage.attempts
    assert_nil stage.data
    receipt = stage.requests.sole
    assert_equal "received", receipt.status
    assert_equal "length", receipt.finish_reason
    assert_equal 17, receipt.usage["output_tokens"]
    assert_equal 2, JSON.parse(receipt.response_body).fetch("motions").size
    assert_equal prior.id, Meeting.find(@meeting.id).minutes_publication_id
    assert_equal [ "First request action", "Final request action" ], @meeting.motions.order(:id).pluck(:description)
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
    clear_enqueued_jobs
    Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    assert_no_enqueued_jobs only: ExtractVotesJob
  end

  test "empty or filtered and missing-finish responses retain usage without treating partial evidence as complete" do
    [ "length", "content_filter", nil ].each_with_index do |reason, index|
      Documents::PublishText.new(@document.reload).call(raw_pages: [ "Source for finish reason #{index}." ],
        page_count: 1, quality: "text", extractor_version: "synthetic_finish_#{index}")
      response = ->(params) do
        provider_response(params).tap do |result|
          result["choices"][0] = { "message" => { "content" => nil }, "finish_reason" => reason }
        end
      end
      with_transport(response: response) { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
      stage = @meeting.minutes_extractions.order(:id).last
      assert_equal "incomplete", stage.status
      assert_equal reason || "missing_finish_reason", stage.error_code
      assert_nil stage.data
      assert_equal 17, stage.requests.sole.usage["output_tokens"]
      assert_nil stage.requests.sole.response_body
      assert_not Minutes::Pipeline.needed?(@meeting.reload, "attendance")
    end
    assert_equal 3, @calls.size
    assert_nil @meeting.reload.minutes_publication_id
  end

  test "transport failure retains a previously committed receipt and uncertain work cannot redispatch" do
    response = ->(params) do
      receipt = MinutesRequest.sole
      assert_equal "dispatched", receipt.status
      assert_nil receipt.finished_at
      assert_equal params.deep_stringify_keys.except("messages"), receipt.request_parameters
      raise Timeout::Error, "synthetic unknown outcome"
    end
    with_transport(response: response) { 3.times { ExtractVotesJob.perform_now(@meeting.id) } }
    assert_equal 1, @calls.size
    stage = @meeting.minutes_extractions.sole
    receipt = MinutesRequest.sole
    assert_equal "uncertain", stage.status
    assert_equal "uncertain", receipt.status
    assert_equal "Timeout::Error", receipt.error_class
    assert_nil receipt.usage
    assert_nil receipt.response_body
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
  end

  test "a process interruption leaves a durable dispatch receipt and no automatic repeat" do
    interrupted = Class.new(Exception)
    with_transport(response: ->(*) { raise interrupted }) do
      assert_raises(interrupted) { ExtractVotesJob.perform_now(@meeting.id) }
    end
    stage = @meeting.minutes_extractions.sole
    assert_equal "running", stage.status
    assert_equal "dispatched", stage.requests.sole.status
    assert_nil stage.requests.sole.finished_at
    with_transport { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal 1, @calls.size
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
  end

  test "receipt creation failure prevents transport and leaves the stage held" do
    fail_receipt = -> { raise "synthetic receipt failure" }
    MinutesRequest.set_callback(:create, :before, fail_receipt)
    begin
      with_transport { ExtractVotesJob.perform_now(@meeting.id) }
    ensure
      MinutesRequest.skip_callback(:create, :before, fail_receipt)
    end
    assert_empty @calls
    assert_equal 0, MinutesRequest.count
    assert_equal "uncertain", @meeting.minutes_extractions.sole.status
  end

  test "receipt completion failure keeps an uncertain charge instead of inviting a replay" do
    fail_completion = -> { raise "synthetic receipt persistence failure" if status == "received" }
    MinutesRequest.set_callback(:update, :before, fail_completion)
    begin
      with_transport { 2.times { ExtractVotesJob.perform_now(@meeting.id) } }
    ensure
      MinutesRequest.skip_callback(:update, :before, fail_completion)
    end
    assert_equal 1, @calls.size
    assert_equal "uncertain", MinutesRequest.sole.status
    assert_equal "RuntimeError", MinutesRequest.sole.error_class
    assert_equal "uncertain", @meeting.minutes_extractions.sole.status
    assert_nil @meeting.minutes_extractions.sole.data
  end

  test "invalid JSON attempts each retain usage and the existing retry ceiling survives nightly checks" do
    malformed = ->(params) { provider_response(params).tap { |response| response["choices"][0]["message"]["content"] = "{" } }
    with_transport(response: malformed) { 3.times { ExtractVotesJob.perform_now(@meeting.id) } }
    stage = @meeting.minutes_extractions.sole
    assert_equal "failed", stage.status
    assert_equal 2, @calls.size
    assert_equal [ 1, 2 ], stage.requests.order(:attempt).pluck(:attempt)
    assert_equal [ "{", "{" ], stage.requests.order(:attempt).pluck(:response_body)
    assert_equal 34, stage.requests.sum { |receipt| receipt.usage.fetch("output_tokens") }
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
    clear_enqueued_jobs
    Scrapers::PipelineRepairSweep.new([ @meeting.id ], parsed_meeting_ids: [ @meeting.id ]).call
    assert_no_enqueued_jobs only: ExtractVotesJob
    assert_equal 2, stage.reload.attempts
  end

  test "receipts survive prompt pruning and source removal and cannot be edited or deleted" do
    with_transport { ExtractVotesJob.perform_now(@meeting.id) }
    receipt = MinutesRequest.sole
    original = receipt.attributes
    11.times do
      PromptRun.create!(prompt_template_key: "extract_votes", ai_model: "synthetic-model", response_body: "synthetic prune receipt")
    end
    assert_equal 10, PromptRun.where(prompt_template_key: "extract_votes").count
    assert_not PromptRun.exists?(source: @meeting, prompt_template_key: "extract_votes")
    @document.destroy!
    @meeting.destroy!
    assert_nil receipt.minutes_extraction.reload.meeting_id
    assert_equal original, receipt.reload.attributes
    assert_not receipt.update(usage: { "output_tokens" => 0 })
    assert_equal original, receipt.reload.attributes
    assert_not receipt.destroy
    assert_equal original, receipt.reload.attributes
    assert_raises(ActiveRecord::DeleteRestrictionError) { receipt.minutes_extraction.destroy! }
    require Rails.root.join("db/migrate/20261108050000_create_minutes_requests")
    migration = CreateMinutesRequests.new
    migration.suppress_messages do
      assert_raises(ActiveRecord::IrreversibleMigration) { migration.migrate(:down) }
    end
    assert_equal original, receipt.reload.attributes
  end

  test "missing provider usage stays unknown instead of being recorded as free" do
    response = ->(params) { provider_response(params).except("usage", "id", "model") }
    with_transport(response: response) { ExtractVotesJob.perform_now(@meeting.id) }
    receipt = MinutesRequest.sole
    assert_equal "received", receipt.status
    assert_equal "completed", receipt.minutes_extraction.status
    assert_nil receipt.usage.fetch("input_tokens")
    assert_nil receipt.usage.fetch("output_tokens")
    assert_nil receipt.provider_response_id
    assert_nil receipt.response_model
    assert_equal 4_000, receipt.request_parameters.fetch("max_completion_tokens")
  end

  test "adding the output ceiling cannot reset preexisting held attempts" do
    attributes = Minutes::Input.new(@meeting).stage_attributes(@meeting, "votes")
    # Reconstruct the pre-receipt manifest: the new request ceiling must not
    # turn an already uncertain request into a fresh extraction identity.
    attributes[:input_manifest]["provider"].delete("max_completion_tokens")
    attributes[:input_key] = Digest::SHA256.hexdigest(JSON.generate(attributes[:input_manifest]))
    stage = MinutesExtraction.create!(attributes.merge(status: "uncertain", attempts: 1))
    with_transport do
      ExtractVotesJob.perform_now(@meeting.id)
      ExtractVotesJob.perform_now(@meeting.id, refresh: true)
    end
    assert_empty @calls
    assert_equal "uncertain", stage.reload.status
    assert_equal 1, stage.attempts
    assert_equal 1, @meeting.minutes_extractions.count
    assert_equal 0, MinutesRequest.count
    assert_not Minutes::Pipeline.needed?(@meeting.reload, "votes")
  end

  test "reentrant delivery does not add a receipt while the first request is in flight" do
    response = ->(params) do
      ExtractVotesJob.perform_now(@meeting.id)
      assert_equal 1, MinutesRequest.count
      assert_equal "dispatched", MinutesRequest.sole.status
      provider_response(params)
    end
    with_transport(response: response) { ExtractVotesJob.perform_now(@meeting.id) }
    assert_equal 1, @calls.size
    assert_equal 1, MinutesRequest.count
    assert_equal "received", MinutesRequest.sole.status
    assert_equal 1, @meeting.minutes_extractions.sole.attempts
  end

  private

  def with_transport(response: nil)
    receiver = self
    client = Object.new
    client.define_singleton_method(:chat) do |parameters:|
      receiver.instance_variable_get(:@calls) << parameters
      response ? response.call(parameters) : receiver.send(:provider_response, parameters)
    end
    OpenAI::Client.stub(:new, client) { yield }
  end

  def provider_response(params)
    attendance = params[:messages].last[:content].include?("voting_members_present")
    data = if attendance
      { voting_members_present: [ "Alex Request", "Blair Request" ], voting_members_absent: [], non_voting_staff: [], guests: [] }
    else
      { motions: [
        { description: "First request action", outcome: "passed", votes: [] },
        { description: "Final request action", outcome: "failed", votes: [ { member: "Alex Request", value: "no" }, { member: "Blair Request", value: "yes" } ] }
      ] }
    end
    { "id" => "synthetic-response", "model" => "synthetic-resolved-model",
      "choices" => [ { "message" => { "content" => data.to_json }, "finish_reason" => "stop" } ],
      "usage" => { "prompt_tokens" => 31, "completion_tokens" => 17, "total_tokens" => 48,
        "prompt_tokens_details" => { "cached_tokens" => 11 }, "completion_tokens_details" => { "reasoning_tokens" => 5 } } }
  end
end
