require "test_helper"

class Topics::ItemDetailsMatcherTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "City Council Work Session", starts_at: 1.day.ago,
      detail_page_url: "https://example.com/work-session")
    @item = @meeting.agenda_items.create!(title: "26-141 WPPI contract extension to 2073", order_index: 1)
  end

  test "matches a rewritten title by a meeting-scoped ID" do
    entry = { "agenda_item_id" => @item.id, "agenda_item_title" => "Power contract", "decision" => "Passed" }
    assert_equal({ @item.id => entry }, match([ entry ]))
  end

  test "supports legacy normalized titles and contextual titles" do
    section = @meeting.agenda_items.create!(title: "ACTION ITEMS", kind: "section", order_index: 0)
    @item.update!(parent: section)
    bare = { "agenda_item_title" => "WPPI contract extension to 2073" }
    contextual = { "agenda_item_title" => @item.display_context_title }
    assert_equal({ @item.id => bare }, match([ bare ]))
    assert_equal({ @item.id => contextual }, match([ contextual ]))
  end

  test "rejects foreign and malformed IDs even when the title matches" do
    other_meeting = Meeting.create!(body_name: "City Council", detail_page_url: "https://example.com/other")
    foreign = other_meeting.agenda_items.create!(title: @item.title, order_index: 1)
    [ foreign.id, "#{@item.id}x", @item.id + 0.5, false ].each do |id|
      assert_empty match([ { "agenda_item_id" => id, "agenda_item_title" => @item.title } ])
    end
  end

  test "uses IDs to distinguish repeated titles and rejects ambiguous legacy titles" do
    duplicate = @meeting.agenda_items.create!(title: @item.title, order_index: 2)
    assert_empty match([ { "agenda_item_title" => @item.title } ])
    entry = { "agenda_item_id" => duplicate.id.to_s, "agenda_item_title" => @item.title }
    assert_equal({ duplicate.id => entry }, match([ entry ]))
  end

  test "rejects conflicting entries for one agenda item" do
    entries = [ "Passed", "Failed" ].map { |decision| { "agenda_item_id" => @item.id, "decision" => decision } }
    assert_empty match(entries)
  end

  test "ignores malformed entries" do
    assert_empty match([ nil, "WPPI", { "agenda_item_title" => 42 } ])
  end

  private

  def match(entries)
    Topics::ItemDetailsMatcher.new(@meeting.agenda_items.includes(:parent).to_a, entries).build
  end
end
