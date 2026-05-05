require "test_helper"
require "rake"

class TopicsRakeTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks unless Rake::Task.task_defined?("topics:seed_category_blocklist")
  end

  test "seed_category_blocklist adds category names to blocklist" do
    TopicBlocklist.where(name: "zoning").destroy_all
    TopicBlocklist.where(name: "infrastructure").destroy_all
    TopicBlocklist.where(name: "finance").destroy_all

    Rake::Task["topics:seed_category_blocklist"].invoke

    assert TopicBlocklist.where(name: "zoning").exists?, "zoning should be blocked"
    assert TopicBlocklist.where(name: "infrastructure").exists?, "infrastructure should be blocked"
    assert TopicBlocklist.where(name: "finance").exists?, "finance should be blocked"
  ensure
    Rake::Task["topics:seed_category_blocklist"].reenable
  end

  test "seed_category_blocklist is idempotent" do
    Rake::Task["topics:seed_category_blocklist"].invoke
    count_after_first = TopicBlocklist.count
    Rake::Task["topics:seed_category_blocklist"].reenable
    Rake::Task["topics:seed_category_blocklist"].invoke
    count_after_second = TopicBlocklist.count

    assert_equal count_after_first, count_after_second
  ensure
    Rake::Task["topics:seed_category_blocklist"].reenable
  end

  test "mark_unsafe_for_reuse normalizes TOPICS env before matching" do
    redevelopment = Topic.create!(name: "Redevelopment", reuse_strategy: "canonical")
    community_visioning = Topic.create!(name: "Community Visioning", reuse_strategy: "canonical")

    previous_topics = ENV["TOPICS"]
    ENV["TOPICS"] = "  ReDeVeLoPmEnT!,  community   visioning  "

    Rake::Task["topics:mark_unsafe_for_reuse"].invoke

    assert_equal "unsafe_for_auto_reuse", redevelopment.reload.reuse_strategy
    assert_equal "unsafe_for_auto_reuse", community_visioning.reload.reuse_strategy
  ensure
    ENV["TOPICS"] = previous_topics
    Rake::Task["topics:mark_unsafe_for_reuse"].reenable
  end

  test "mark_unsafe_for_reuse aborts when TOPICS is blank" do
    previous_topics = ENV["TOPICS"]
    ENV["TOPICS"] = "   "

    stdout, stderr = capture_io do
      assert_raises(SystemExit) do
        Rake::Task["topics:mark_unsafe_for_reuse"].invoke
      end
    end

    assert_match(/Usage: TOPICS='redevelopment,community visioning' bin\/rails topics:mark_unsafe_for_reuse/, stderr)
  ensure
    ENV["TOPICS"] = previous_topics
    Rake::Task["topics:mark_unsafe_for_reuse"].reenable
  end

  test "split_broad_topic uses reusable topics as existing candidates" do
    broad = Topic.create!(name: "redevelopment", status: "approved")
    reusable_candidate = Topic.create!(name: "former hamilton site", status: "approved")
    Topic.create!(name: "legacy topic", status: "approved", reuse_strategy: "unsafe_for_auto_reuse")

    meeting = Meeting.create!(body_name: "planning commission", starts_at: Time.current, detail_page_url: "https://example.com/meetings/1")
    item = AgendaItem.create!(title: "Redevelopment discussion", summary: "Hamilton parcel update", meeting: meeting)
    AgendaItemTopic.create!(agenda_item: item, topic: broad)

    captured_calls = []
    original_call = Topics::FindOrCreateService.method(:call)

    capture_io do
      ai_service = Object.new
      ai_service.define_singleton_method(:re_extract_item_topics) do |**_kwargs|
        { "topic_worthy" => true, "tags" => [ "Former Hamilton Site" ] }.to_json
      end

      Ai::OpenAiService.stub(:new, ai_service) do
        Topics::FindOrCreateService.define_singleton_method(:call) do |*args, **kwargs|
          captured_calls << [ args, kwargs ]
          reusable_candidate
        end

        Rake::Task["topics:split_broad_topic"].invoke(broad.name)
      end
    end

    assert_equal 1, captured_calls.length
    assert_equal [ "Former Hamilton Site" ], captured_calls.first.first
    assert_equal(
      {
        item_title: item.title,
        item_summary: item.summary,
        meeting_body_name: meeting.body_name,
        document_text: "",
        existing_topics: [ "former hamilton site" ]
      },
      captured_calls.first.last
    )
  ensure
    Topics::FindOrCreateService.singleton_class.send(:define_method, :call, original_call)
    Rake::Task["topics:split_broad_topic"].reenable
  end

  test "split_broad_topic reuses duplicate tags within the same run" do
    broad = Topic.create!(name: "redevelopment", status: "approved")

    meeting = Meeting.create!(body_name: "planning commission", starts_at: Time.current, detail_page_url: "https://example.com/meetings/2")
    item_one = AgendaItem.create!(title: "First redevelopment item", summary: "First summary", meeting: meeting)
    item_two = AgendaItem.create!(title: "Second redevelopment item", summary: "Second summary", meeting: meeting)
    AgendaItemTopic.create!(agenda_item: item_one, topic: broad)
    AgendaItemTopic.create!(agenda_item: item_two, topic: broad)

    capture_io do
      ai_service = Object.new
      ai_service.define_singleton_method(:re_extract_item_topics) do |**_kwargs|
        { "topic_worthy" => true, "tags" => [ "Former Hamilton Site" ] }.to_json
      end

      Ai::OpenAiService.stub(:new, ai_service) do
        Rake::Task["topics:split_broad_topic"].invoke(broad.name)
      end
    end

    topic = Topic.find_by(name: "former hamilton site")
    assert topic.present?
    assert_equal [ topic ], item_one.reload.topics.to_a
    assert_equal [ topic ], item_two.reload.topics.to_a
    assert_equal 2, AgendaItemTopic.where(topic: topic).count
  ensure
    Rake::Task["topics:split_broad_topic"].reenable
  end
end
