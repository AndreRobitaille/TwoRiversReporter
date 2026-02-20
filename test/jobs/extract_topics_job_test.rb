require "test_helper"
require "minitest/mock"

class ExtractTopicsJobTest < ActiveJob::TestCase
  test "skips items marked topic_worthy false" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/1"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Operator License Renewal - Jane Doe", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Licensing",
        "tags" => [ "operator license renewal" ],
        "topic_worthy" => false,
        "confidence" => 0.9
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_no_difference "Topic.count" do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "skips items categorized as Routine" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/2"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Accept Monthly Financial Report", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Routine",
        "tags" => [ "monthly financial report" ],
        "topic_worthy" => false,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_no_difference "Topic.count" do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "creates topics for items marked topic_worthy true" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/3"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Lakefront Development Proposal", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "lakefront development" ],
        "topic_worthy" => true,
        "confidence" => 0.85
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_difference "Topic.count", 1 do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "includes linked document text in extraction" do
    meeting = Meeting.create!(
      body_name: "Zoning Board", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/4"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "PUBLIC HEARING", order_index: 1)
    doc = MeetingDocument.create!(
      meeting: meeting, document_type: "agenda_pdf",
      extracted_text: "Appeal of Riverside Seafood Inc to construct an accessory structure at 123 Main St"
    )
    AgendaItemDocument.create!(agenda_item: item, meeting_document: doc)

    captured_text = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "riverside seafood zoning appeal" ],
        "topic_worthy" => true,
        "confidence" => 0.9
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      captured_text = text
      true
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    assert_includes captured_text, "Riverside Seafood"
    assert_includes captured_text, "Attached Document (agenda_pdf)"
    mock_ai.verify
  end

  test "includes meeting-level packet text as context" do
    meeting = Meeting.create!(
      body_name: "Zoning Board", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/5"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "PUBLIC HEARING", order_index: 1)
    # Packet doc NOT linked to any item
    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "Zoning variance request for 456 Oak Ave commercial expansion"
    )

    captured_kwargs = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "commercial expansion zoning variance" ],
        "topic_worthy" => true,
        "confidence" => 0.85
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      captured_kwargs = kwargs
      true
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    assert_includes captured_kwargs[:meeting_documents_context], "commercial expansion"
    assert_includes captured_kwargs[:meeting_documents_context], "packet_pdf"
    mock_ai.verify
  end

  test "works normally when no documents have text" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/6"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Discussion", order_index: 1)
    # Document with no extracted text
    MeetingDocument.create!(meeting: meeting, document_type: "packet_pdf", extracted_text: nil)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "city budget" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      true
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    assert_difference "Topic.count", 1 do
      RetrievalService.stub :new, retrieval_stub do
        Ai::OpenAiService.stub :new, mock_ai do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    mock_ai.verify
  end

  test "refines catch-all topic into substantive topic when significant" do
    meeting = Meeting.create!(
      body_name: "Zoning Board", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/7"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "PUBLIC HEARING", order_index: 1)
    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "Appeal to construct commercial accessory structure in the front yard"
    )

    # Create the catch-all topic
    catchall_topic = Topic.create!(name: "height and area exceptions", status: :approved, review_status: :approved)

    # Pass 1 response: AI tags with catch-all
    extract_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "height and area exceptions" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    # Pass 2 response: AI refines to substantive topic
    refine_response = { "action" => "replace", "topic_name" => "zoning appeal" }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, extract_response do |text, **kwargs|
      true
    end
    mock_ai.expect :refine_catchall_topic, refine_response do |**kwargs|
      kwargs[:catchall_topic] == "height and area exceptions"
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    # The catch-all link should be replaced with the substantive topic
    item_topics = item.topics.reload.pluck(:canonical_name)
    assert_includes item_topics, "zoning appeal"
    refute_includes item_topics, "height and area exceptions"
    mock_ai.verify
  end

  test "keeps catch-all topic when refinement says minor" do
    meeting = Meeting.create!(
      body_name: "Zoning Board", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/8"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "FENCE PERMIT", order_index: 1)
    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "Standard 6-foot privacy fence along rear property line"
    )

    catchall_topic = Topic.create!(name: "height and area exceptions", status: :approved, review_status: :approved)

    extract_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "height and area exceptions" ],
        "topic_worthy" => true,
        "confidence" => 0.7
      } ]
    }.to_json

    refine_response = { "action" => "keep" }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, extract_response do |text, **kwargs|
      true
    end
    mock_ai.expect :refine_catchall_topic, refine_response do |**kwargs|
      true
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    item_topics = item.topics.reload.pluck(:canonical_name)
    assert_includes item_topics, "height and area exceptions"
    mock_ai.verify
  end
end
