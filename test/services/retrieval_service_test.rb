require "test_helper"

class RetrievalServiceTest < ActiveSupport::TestCase
  setup do
    @service = RetrievalService.new

    # Create sources
    @source1 = KnowledgeSource.create!(title: "City Plan", source_type: "pdf", verification_notes: "Official", active: true)
    @source2 = KnowledgeSource.create!(title: "Resident Note", source_type: "note", active: true)

    # Create chunks with embeddings
    # We mock embeddings as arrays of floats for VectorService
    @chunk1 = KnowledgeChunk.create!(knowledge_source: @source1, content: "A" * 1000, embedding: [ 1.0, 0.0, 0.0 ])
    @chunk2 = KnowledgeChunk.create!(knowledge_source: @source1, content: "B" * 1000, embedding: [ 0.9, 0.1, 0.0 ])
    @chunk3 = KnowledgeChunk.create!(knowledge_source: @source2, content: "C" * 1000, embedding: [ 0.8, 0.2, 0.0 ])
    @chunk4 = KnowledgeChunk.create!(knowledge_source: @source2, content: "D" * 1000, embedding: [ 0.7, 0.3, 0.0 ])
    @chunk5 = KnowledgeChunk.create!(knowledge_source: @source1, content: "E" * 1000, embedding: [ 0.6, 0.4, 0.0 ])
    @chunk6 = KnowledgeChunk.create!(knowledge_source: @source2, content: "F" * 1000, embedding: [ 0.5, 0.5, 0.0 ])
  end

  test "retrieve_topic_context respects limit" do
    # Mock embedding service to return a query vector that matches our chunks
    # Since we use dot product/cosine, [1,0,0] matches chunk1 best.

    mock_embedding_service = Object.new
    def mock_embedding_service.embed(text); [ 1.0, 0.0, 0.0 ]; end

    @service.instance_variable_set(:@embedding_service, mock_embedding_service)

    results = @service.retrieve_topic_context(topic: nil, query_text: "test", limit: 3, max_chars: 10000)

    assert_equal 3, results.size
    assert_equal @chunk1, results[0][:chunk]
    assert_equal @chunk2, results[1][:chunk]
    assert_equal @chunk3, results[2][:chunk]
  end

  test "retrieve_topic_context respects max_chars" do
    mock_embedding_service = Object.new
    def mock_embedding_service.embed(text); [ 1.0, 0.0, 0.0 ]; end
    @service.instance_variable_set(:@embedding_service, mock_embedding_service)

    # Chunks are 1000 chars each.
    # Limit 5, max_chars 2500. Should return 2 chunks (2000 chars).
    results = @service.retrieve_topic_context(topic: nil, query_text: "test", limit: 5, max_chars: 2500)

    assert_equal 2, results.size
    assert_equal @chunk1, results[0][:chunk]
    assert_equal @chunk2, results[1][:chunk]
  end

  test "retrieve_topic_context is deterministic on ties" do
    # Create two chunks with identical content/embedding but different IDs
    chunk_a = KnowledgeChunk.create!(knowledge_source: @source1, content: "Tie", embedding: [ 0.0, 1.0, 0.0 ])
    chunk_b = KnowledgeChunk.create!(knowledge_source: @source1, content: "Tie", embedding: [ 0.0, 1.0, 0.0 ])

    # Query vector [0, 1, 0] matches both perfectly
    mock_embedding_service = Object.new
    def mock_embedding_service.embed(text); [ 0.0, 1.0, 0.0 ]; end
    @service.instance_variable_set(:@embedding_service, mock_embedding_service)

    # We expect ID sort to break ties. VectorService sorts by score DESC, then ID ASC.
    # ID order depends on creation order usually.
    first_id = [ chunk_a.id, chunk_b.id ].min
    second_id = [ chunk_a.id, chunk_b.id ].max

    results = @service.retrieve_topic_context(topic: nil, query_text: "test", limit: 2, max_chars: 10000)

    assert_equal 2, results.size
    assert_equal first_id, results[0][:chunk].id
    assert_equal second_id, results[1][:chunk].id
  end

  test "format_topic_context includes provenance" do
    results = [
      { chunk: @chunk1, score: 0.9 },
      { chunk: @chunk3, score: 0.8 }
    ]

    formatted = @service.format_topic_context(results)

    assert_equal 2, formatted.size

    # Verify Source 1 (Verified)
    assert_match /Source: City Plan/, formatted[0]
    assert_match /Status: VERIFIED/, formatted[0]
    assert_match /ID: #{@source1.id}/, formatted[0]

    # Verify Source 2 (Unverified)
    assert_match /Source: Resident Note/, formatted[1]
    assert_match /Status: UNVERIFIED/, formatted[1]
    assert_match /ID: #{@source2.id}/, formatted[1]
  end
end
