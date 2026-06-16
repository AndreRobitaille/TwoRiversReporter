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

  test "routes unsafe redevelopment tags to former hamilton site when extraction context is strong" do
    meeting = Meeting.create!(
      body_name: "Planning Commission", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/3b"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "1",
      title: "Former Hamilton site redevelopment",
      summary: "Visioning for the former Hamilton property",
      order_index: 1
    )
    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "Former Hamilton site redevelopment discussion and site planning details"
    )
    former_hamilton = Topic.create!(name: "former hamilton site", status: "approved")
    unsafe_redevelopment = Topic.create!(name: "redevelopment", status: "approved", reuse_strategy: "unsafe_for_auto_reuse")

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Development",
        "tags" => [ "Redevelopment" ],
        "topic_worthy" => true,
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

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    item_topics = item.topics.reload
    assert_includes item_topics, former_hamilton
    refute_includes item_topics, unsafe_redevelopment
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

  test "excludes structural rows while preserving parent section context for substantive items" do
    meeting = Meeting.create!(
      body_name: "Planning Commission", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/4b"
    )
    section = AgendaItem.create!(meeting: meeting, number: "5", title: "NEW BUSINESS", kind: "section", order_index: 1)
    child = AgendaItem.create!(meeting: meeting, parent: section, number: "5A", title: "Riverside Redevelopment", kind: "item", order_index: 2)

    captured_text = nil
    ai_response = {
      "items" => [ {
        "id" => child.id,
        "category" => "Development",
        "tags" => [ "riverside redevelopment" ],
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

    assert_includes captured_text, "ID: #{child.id}"
    assert_includes captured_text, "Title: Riverside Redevelopment"
    assert_includes captured_text, "Section Context: NEW BUSINESS"
    refute_includes captured_text, "ID: #{section.id}"
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

  test "passes only reusable topic names to extract_topics" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/4c"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "PUBLIC HEARING", order_index: 1)

    reusable_topic = Topic.create!(
      name: "reusable topic",
      status: "approved",
      lifecycle_status: "active",
      reuse_strategy: "canonical",
      resident_impact_score: 5,
      last_activity_at: 1.day.ago
    )
    unsafe_topic = Topic.create!(
      name: "unsafe topic",
      status: "approved",
      lifecycle_status: "active",
      reuse_strategy: "unsafe_for_auto_reuse",
      resident_impact_score: 5,
      last_activity_at: 1.day.ago
    )

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "new development" ],
        "topic_worthy" => true,
        "confidence" => 0.9
      } ]
    }.to_json

    captured_existing_topics = nil
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |text, **kwargs|
      captured_existing_topics = kwargs[:existing_topics]
      text.is_a?(String)
    end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    assert_includes captured_existing_topics, reusable_topic.name
    assert_not_includes captured_existing_topics, unsafe_topic.name
    mock_ai.verify
  end

  test "returns early when no substantive agenda items exist" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/6"
    )
    MeetingDocument.create!(meeting: meeting, document_type: "packet_pdf", extracted_text: nil)

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); flunk "should not retrieve context"; end
    def retrieval_stub.format_context(*args); flunk "should not format context"; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, ->(*) { raise "should not instantiate AI when there are no substantive agenda items" } do
        assert_no_difference "Topic.count" do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    assert_equal "empty", meeting.reload.processing_state["topics_extraction_status"]
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

  test "prefers minutes over packet in meeting document context" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/minutes-pref"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Discussion", order_index: 1)

    # Both packet and minutes exist — minutes should win
    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "PACKET_MARKER consent agenda embedded committee minutes financial reports"
    )
    MeetingDocument.create!(
      meeting: meeting, document_type: "minutes_pdf",
      extracted_text: "MINUTES_MARKER council discussed budget and voted to approve"
    )

    captured_kwargs = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "city budget" ],
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

    # Minutes should be included, packet should NOT
    assert_includes captured_kwargs[:meeting_documents_context], "MINUTES_MARKER"
    refute_includes captured_kwargs[:meeting_documents_context], "PACKET_MARKER"
    mock_ai.verify
  end

  test "minutes text uses 25K truncation limit" do
    meeting = Meeting.create!(
      body_name: "Advisory Recreation Board", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/minutes-25k"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Parks Discussion", order_index: 1)

    # Create minutes text that's 15K chars — above old 8K limit
    long_minutes = "MINUTES_START " + ("discussion about park improvements. " * 400) + " MINUTES_END"
    MeetingDocument.create!(
      meeting: meeting, document_type: "minutes_pdf",
      extracted_text: long_minutes
    )

    captured_kwargs = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Recreation",
        "tags" => [ "park improvements" ],
        "topic_worthy" => true,
        "confidence" => 0.8
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

    # Should include text beyond the old 8K limit
    assert_includes captured_kwargs[:meeting_documents_context], "MINUTES_START"
    assert_includes captured_kwargs[:meeting_documents_context], "MINUTES_END"
    assert captured_kwargs[:meeting_documents_context].length > 8000
    mock_ai.verify
  end

  test "falls back to packet text when no minutes exist" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/packet-fallback"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Zoning Request", order_index: 1)
    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "PACKET_ONLY zoning variance application details"
    )

    captured_kwargs = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "zoning variance" ],
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

    assert_includes captured_kwargs[:meeting_documents_context], "PACKET_ONLY"
    assert_includes captured_kwargs[:meeting_documents_context], "packet_pdf"
    mock_ai.verify
  end

  test "catch-all refinement uses minutes over packet for document text" do
    meeting = Meeting.create!(
      body_name: "Zoning Board", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/catchall-minutes"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "PUBLIC HEARING", order_index: 1)

    MeetingDocument.create!(
      meeting: meeting, document_type: "packet_pdf",
      extracted_text: "PACKET_NOISE consent agenda financial reports"
    )
    MeetingDocument.create!(
      meeting: meeting, document_type: "minutes_pdf",
      extracted_text: "MINUTES_CONTENT appeal to construct commercial structure at 456 Oak Ave"
    )

    catchall_topic = Topic.create!(name: "height and area exceptions", status: :approved, review_status: :approved)

    extract_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Zoning",
        "tags" => [ "height and area exceptions" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    captured_refine_kwargs = nil
    refine_response = { "action" => "replace", "topic_name" => "commercial zoning appeal" }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, extract_response do |text, **kwargs|
      true
    end
    mock_ai.expect :refine_catchall_topic, refine_response do |**kwargs|
      captured_refine_kwargs = kwargs
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

    assert_includes captured_refine_kwargs[:document_text], "MINUTES_CONTENT"
    refute_includes captured_refine_kwargs[:document_text], "PACKET_NOISE"
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

  test "records topics extraction status and timestamp on success" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/status"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Discussion", order_index: 1)

    ai_response = { "items" => [ { "id" => item.id, "category" => "Finance", "tags" => [ "city budget" ], "topic_worthy" => true, "confidence" => 0.8 } ] }.to_json
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    state = meeting.reload.processing_state
    assert_equal "processed", state["topics_extraction_status"]
    assert_not_nil state["topics_extracted_at"]
  end

  test "records processed status for non-empty successful extraction" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/status-processed"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Discussion", order_index: 1)

    ai_response = { "items" => [ { "id" => item.id, "category" => "Finance", "tags" => [ "city budget" ], "topic_worthy" => true, "confidence" => 0.8 } ] }.to_json
    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs| true end

    retrieval_stub = Object.new
    def retrieval_stub.retrieve_context(*args, **kwargs); []; end
    def retrieval_stub.format_context(*args); ""; end

    RetrievalService.stub :new, retrieval_stub do
      Ai::OpenAiService.stub :new, mock_ai do
        ExtractTopicsJob.perform_now(meeting.id)
      end
    end

    state = meeting.reload.processing_state
    assert_equal "processed", state["topics_extraction_status"]
    assert_not_nil state["topics_extracted_at"]
  end

  test "rejects citywide budget variant tags for room tax commission budget review" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/citywide-budget"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Review", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "citywide budget", "city budget update" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
      true
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

  test "rejects overall city budget variant tags for generic rtc budget review" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/overall-city-budget"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "RTC BUDGET REVIEW", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "overall city budget" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
      true
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

  test "does not reject room tax budget tags" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/room-tax-budget"
    )
    item = AgendaItem.create!(meeting: meeting, number: "1", title: "Budget Review", order_index: 1)

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "room tax budget" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

  test "records topics extraction empty when no substantive agenda items exist" do
    meeting = Meeting.create!(
      body_name: "City Council", meeting_type: "Regular",
      starts_at: 1.day.from_now, status: "agenda_posted",
      detail_page_url: "http://example.com/m/missing-topics"
    )

    assert_no_difference "Topic.count" do
      RetrievalService.stub :new, ->(*) { flunk "should not retrieve context" } do
        Ai::OpenAiService.stub :new, ->(*) { flunk "should not instantiate AI when there are no substantive agenda items" } do
          ExtractTopicsJob.perform_now(meeting.id)
        end
      end
    end

    assert_equal "empty", meeting.reload.processing_state["topics_extraction_status"]
  end

  test "passes meeting body and date context to topic extraction" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/room-tax"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "4.",
      title: "BUDGET REVIEW (Action Item)",
      order_index: 4,
      kind: "item"
    )

    captured_kwargs = nil
    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "room tax budget" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    assert_includes captured_kwargs[:meeting_context], "Meeting body: Room Tax Commission Meeting"
    assert_includes captured_kwargs[:meeting_context], "Meeting date: 2026-06-23"
    mock_ai.verify
  end

  test "does not link room tax commission budget review to city budget without explicit citywide scope" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/room-tax-budget"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "4.",
      title: "BUDGET REVIEW (Action Item)",
      order_index: 4,
      kind: "item"
    )
    Topic.create!(name: "city budget", status: "approved", review_status: "approved")

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
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    refute_includes item.topics.reload.pluck(:canonical_name), "city budget"
    refute AgendaItemTopic.joins(:topic).where(agenda_item: item, topics: { canonical_name: "city budget" }).exists?
    refute_equal "parse_error", meeting.reload.processing_state["topics_extraction_status"]
    mock_ai.verify
  end

  test "does not link room tax commission city budget review variant to city budget" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/room-tax-budget-variant"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "4.",
      title: "BUDGET REVIEW (Action Item)",
      order_index: 4,
      kind: "item"
    )
    Topic.create!(name: "city budget", status: "approved", review_status: "approved")

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "city budget review" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    refute_includes item.topics.reload.pluck(:canonical_name), "city budget"
    mock_ai.verify
  end

  test "links room tax budget for room tax commission budget review" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/room-tax-budget-allowed"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "4.",
      title: "BUDGET REVIEW (Action Item)",
      order_index: 4,
      kind: "item"
    )
    Topic.create!(name: "room tax budget", status: "approved", review_status: "approved")

    ai_response = {
      "items" => [ {
        "id" => item.id,
        "category" => "Finance",
        "tags" => [ "room tax budget" ],
        "topic_worthy" => true,
        "confidence" => 0.8
      } ]
    }.to_json

    mock_ai = Minitest::Mock.new
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    assert_includes item.topics.reload.pluck(:canonical_name), "room tax budget"
    mock_ai.verify
  end

  test "allows room tax commission budget review to city budget when explicit citywide scope exists" do
    meeting = Meeting.create!(
      body_name: "Room Tax Commission Meeting",
      meeting_type: "regular",
      starts_at: Time.zone.parse("2026-06-23 16:00:00"),
      status: "upcoming",
      detail_page_url: "http://example.com/room-tax-budget-allow"
    )
    item = AgendaItem.create!(
      meeting: meeting,
      number: "4.",
      title: "BUDGET REVIEW (Action Item)",
      order_index: 4,
      kind: "item"
    )
    AgendaItemDocument.create!(agenda_item: item, meeting_document: MeetingDocument.create!(meeting: meeting, document_type: "packet_pdf", extracted_text: "General Fund citywide tax levy discussion for the room tax commission budget review"))
    Topic.create!(name: "city budget", status: "approved", review_status: "approved")

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
    mock_ai.expect :extract_topics, ai_response do |_text, **kwargs|
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

    assert_includes item.topics.reload.pluck(:canonical_name), "city budget"
    mock_ai.verify
  end
end
