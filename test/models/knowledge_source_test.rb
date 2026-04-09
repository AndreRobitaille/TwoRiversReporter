require "test_helper"

class KnowledgeSourceTest < ActiveSupport::TestCase
  test "origin must be one of manual, extracted, pattern" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "invalid")
    assert_not source.valid?
    assert_includes source.errors[:origin], "is not included in the list"
  end

  test "status must be one of proposed, approved, blocked" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", status: "invalid")
    assert_not source.valid?
    assert_includes source.errors[:status], "is not included in the list"
  end

  test "reasoning is required for extracted origin" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "extracted", reasoning: nil)
    assert_not source.valid?
    assert_includes source.errors[:reasoning], "can't be blank"
  end

  test "reasoning is required for pattern origin" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "pattern", reasoning: nil)
    assert_not source.valid?
    assert_includes source.errors[:reasoning], "can't be blank"
  end

  test "reasoning is not required for manual origin" do
    source = KnowledgeSource.new(title: "Test", source_type: "note", body: "content", origin: "manual")
    source.valid?
    assert_not_includes source.errors[:reasoning] || [], "can't be blank"
  end

  test "scope approved returns only approved sources" do
    approved = KnowledgeSource.create!(title: "Approved", source_type: "note", body: "x", status: "approved", origin: "manual")
    KnowledgeSource.create!(title: "Proposed", source_type: "note", body: "x", status: "proposed", origin: "extracted", reasoning: "test")

    assert_includes KnowledgeSource.approved, approved
    assert_equal 1, KnowledgeSource.approved.count
  end

  test "scope proposed returns only proposed sources" do
    KnowledgeSource.create!(title: "Approved", source_type: "note", body: "x", status: "approved", origin: "manual")
    proposed = KnowledgeSource.create!(title: "Proposed", source_type: "note", body: "x", status: "proposed", origin: "extracted", reasoning: "test")

    assert_includes KnowledgeSource.proposed, proposed
    assert_equal 1, KnowledgeSource.proposed.count
  end

  test "scope extracted returns only extracted origin" do
    KnowledgeSource.create!(title: "Manual", source_type: "note", body: "x", status: "approved", origin: "manual")
    extracted = KnowledgeSource.create!(title: "Extracted", source_type: "note", body: "x", status: "approved", origin: "extracted", reasoning: "test")

    assert_includes KnowledgeSource.extracted, extracted
    assert_equal 1, KnowledgeSource.extracted.count
  end
end
