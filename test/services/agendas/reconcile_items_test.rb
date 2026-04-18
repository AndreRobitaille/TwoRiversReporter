require "test_helper"

module Agendas
  class ReconcileItemsTest < ActiveSupport::TestCase
    test "updates root and legacy-safe rows in place while preserving ids" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/reconcile-service")
      parent = meeting.agenda_items.create!(number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 1)
      child = meeting.agenda_items.create!(number: "A.", title: "Old Harbor Title", kind: "item", parent: parent, order_index: 2)

      candidates = [
        { number: "7.", title: "ACTION ITEMS", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil },
        { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: "7.:ACTION ITEMS", order_index: 2, summary: nil, recommended_action: "Approve resolution" }
      ]

      assert_raises(Agendas::ReconcileItems::AmbiguousMatchError) do
        Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      end

      assert_equal [
        [parent.id, "7.", "ACTION ITEMS", "section", nil, 1],
        [child.id, "A.", "Old Harbor Title", "item", parent.id, 2]
      ], meeting.reload.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
    end

    test "reuses legacy nil-kind substantive rows when titles and order match" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/legacy-kind")
      meeting.agenda_items.create!(number: "A.", title: "Harbor Resolution", kind: nil, order_index: 2)

      candidates = [
        { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: nil, order_index: 2, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call

      assert_equal 1, meeting.agenda_items.count
      assert_equal "item", meeting.agenda_items.first.reload.kind
    end

    test "does not reuse a lone legacy flat row when title and order do not safely match" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/legacy-mismatch")
      legacy = meeting.agenda_items.create!(number: "A.", title: "Old Harbor Title", kind: nil, order_index: 2)

      candidates = [
        { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: nil, order_index: 4, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call

      assert_equal 1, meeting.agenda_items.count
      assert_nil meeting.agenda_items.find_by(id: legacy.id)
      assert_equal "Harbor Resolution", meeting.agenda_items.find_by(number: "A.", title: "Harbor Resolution")&.title
      assert_equal [ "item" ], meeting.agenda_items.order(:id).pluck(:kind)
    end

    test "raises when number alone is ambiguous" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/wrong-row")
      meeting.agenda_items.create!(number: "A.", title: "Old Harbor Title", kind: "item", order_index: 2)
      meeting.agenda_items.create!(number: "A.", title: "Different Harbor Title", kind: "item", order_index: 3)

      candidates = [
        { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: nil, order_index: 4, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      assert_raises(Agendas::ReconcileItems::AmbiguousMatchError) do
        Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      end
    end

    test "raises when multiple rows match under the same resolved parent" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/parent-ambiguous")
      parent = meeting.agenda_items.create!(number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 1)
      meeting.agenda_items.create!(number: "A.", title: "First Harbor Title", kind: "item", parent: parent, order_index: 2)
      meeting.agenda_items.create!(number: "A.", title: "Second Harbor Title", kind: "item", parent: parent, order_index: 3)

      candidates = [
        { number: "7.", title: "ACTION ITEMS", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] },
        { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: "7.:ACTION ITEMS", order_index: 4, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      assert_raises(Agendas::ReconcileItems::AmbiguousMatchError) do
        Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      end
    end

    test "updates a root-level structured row in place when its title and order change" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/root-structured")
      section = meeting.agenda_items.create!(number: "1.", title: "OLD TITLE", kind: "section", order_index: 9)

      candidates = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call

      assert_equal 1, meeting.agenda_items.count
      assert_equal section.id, meeting.agenda_items.first.id
      assert_equal "CALL TO ORDER", section.reload.title
      assert_equal 1, section.order_index
    end

    test "fails closed when a structured child row under the same parent only matches by number" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/structured-mismatch")
      parent = meeting.agenda_items.create!(number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 1)
      existing = meeting.agenda_items.create!(number: "A.", title: "Old Harbor Title", kind: "item", parent: parent, order_index: 2)

      candidates = [
        { number: "7.", title: "ACTION ITEMS", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] },
        { number: "A.", title: "Harbor Resolution", kind: "item", parent_key: "7.:ACTION ITEMS", order_index: 4, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      assert_raises(Agendas::ReconcileItems::AmbiguousMatchError) do
        Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      end

      assert_equal [
        [parent.id, "7.", "ACTION ITEMS", "section", nil, 1],
        [existing.id, "A.", "Old Harbor Title", "item", parent.id, 2]
      ], meeting.reload.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
    end

    test "digest changes when linked documents change" do
      base = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] }
      ]
      with_links = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [ "attachments/a.pdf" ] }
      ]

      refute_equal Agendas::ReconcileItems.digest_for_candidates(base), Agendas::ReconcileItems.digest_for_candidates(with_links)
    end

    test "removes stale unmatched rows when they are safe to delete" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/stale-safe")
      stale = meeting.agenda_items.create!(number: "9.", title: "OLD BUSINESS", kind: "section", order_index: 9)

      candidates = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call

      assert_nil meeting.agenda_items.find_by(id: stale.id)
      assert_equal [ [meeting.agenda_items.first.id, "1.", "CALL TO ORDER"] ], meeting.agenda_items.order(:id).pluck(:id, :number, :title)
      assert_equal Agendas::ReconcileItems.digest_for_candidates(candidates), meeting.reload.agenda_structure_digest
    end

    test "raises and rolls back when a stale unmatched row is not safe to delete" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/stale-unsafe")
      stale = meeting.agenda_items.create!(number: "9.", title: "OLD BUSINESS", kind: "item", order_index: 9)
      topic = Topic.create!(name: "Stale Topic")
      AgendaItemTopic.create!(agenda_item: stale, topic: topic)
      motion = meeting.motions.create!(agenda_item: stale, description: "Refer to committee")

      original_digest = meeting.agenda_structure_digest
      original_items = meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)

      candidates = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      assert_raises(Agendas::ReconcileItems::UnsafeUnmatchedAgendaItemError) do
        Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      end

      meeting.reload

      assert_nil meeting.agenda_structure_digest
      assert_equal original_items, meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
      assert_equal stale.id, motion.reload.agenda_item_id
    end

    test "removes a stale subtree when the parent and descendants are all safely unmatched" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/stale-subtree-safe")
      parent = meeting.agenda_items.create!(number: "7.", title: "ACTION ITEMS", kind: "section", order_index: 1)
      child = meeting.agenda_items.create!(number: "A.", title: "OLD CHILD", kind: "item", parent: parent, order_index: 2)

      candidates = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call

      assert_nil meeting.agenda_items.find_by(id: parent.id)
      assert_nil meeting.agenda_items.find_by(id: child.id)
      assert_equal [ [meeting.agenda_items.first.id, "1.", "CALL TO ORDER"] ], meeting.agenda_items.order(:id).pluck(:id, :number, :title)
    end

    test "raises and rolls back when a stale unmatched row still has topic appearances" do
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current, status: "parsed", detail_page_url: "http://example.com/stale-topic-appearance")
      stale = meeting.agenda_items.create!(number: "9.", title: "OLD BUSINESS", kind: "item", order_index: 9)
      topic = Topic.create!(name: "Stale Topic Appearance")
      TopicAppearance.create!(topic: topic, meeting: meeting, agenda_item: stale, evidence_type: "agenda_item", appeared_at: Time.current)

      original_digest = meeting.agenda_structure_digest
      original_items = meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)

      candidates = [
        { number: "1.", title: "CALL TO ORDER", kind: "section", parent_key: nil, order_index: 1, summary: nil, recommended_action: nil, linked_documents: [] }
      ]

      assert_raises(Agendas::ReconcileItems::UnsafeUnmatchedAgendaItemError) do
        Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
      end

      meeting.reload

      assert_nil meeting.agenda_structure_digest
      assert_equal original_items, meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
      assert_equal stale.id, TopicAppearance.find_by(topic: topic, meeting: meeting)&.agenda_item_id
    end
  end
end
