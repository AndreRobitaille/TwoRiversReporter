require "test_helper"
require "securerandom"

module Admin
  class TopicsReviewTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", admin: true)
      sign_in_as_admin(@admin)

      # Create sample topics
      @proposed_topic = Topic.create!(name: "Proposed Topic", status: "proposed", review_status: "proposed")
      @approved_topic = Topic.create!(name: "Approved Topic", status: "approved", review_status: "approved")
      @blocked_topic = Topic.create!(name: "Blocked Topic", status: "blocked", review_status: "blocked")
    end

    def proposed_topic
      Topic.create!(name: "proposed #{SecureRandom.hex(4)}",
                    status: "proposed", review_status: "proposed", lifecycle_status: "active")
    end

    test "should filter by review_status" do
      get admin_topics_url(review_status: "proposed")
      assert_response :success
      assert_select "a[href=?]", admin_topic_path(@proposed_topic), text: @proposed_topic.name
      assert_select "a", text: @approved_topic.name, count: 0

      get admin_topics_url(review_status: "approved")
      assert_response :success
      assert_select "a", text: @proposed_topic.name, count: 0
      assert_select "a[href=?]", admin_topic_path(@approved_topic), text: @approved_topic.name
    end

    test "should approve proposed topic" do
      assert_difference "TopicReviewEvent.count", 1 do
        post approve_admin_topic_url(@proposed_topic)
      end

      @proposed_topic.reload
      assert_equal "approved", @proposed_topic.status
      assert_equal "approved", @proposed_topic.review_status

      event = TopicReviewEvent.order(:created_at).last
      assert_equal @admin, event.user
      assert_equal @proposed_topic, event.topic
      assert_equal "approved", event.action
    end

    test "should block proposed topic" do
      assert_difference "TopicReviewEvent.count", 1 do
        post block_admin_topic_url(@proposed_topic)
      end

      @proposed_topic.reload
      assert_equal "blocked", @proposed_topic.status
      assert_equal "blocked", @proposed_topic.review_status

      event = TopicReviewEvent.order(:created_at).last
      assert_equal "blocked", event.action
    end

    test "blocking a topic adds its name to blocklist" do
      topic = Topic.create!(name: "Public Comment Period", status: "proposed", review_status: "proposed")

      assert_difference "TopicBlocklist.count" do
        post block_admin_topic_url(topic)
      end

      assert TopicBlocklist.exists?(name: "public comment period"),
        "Blocked topic name should be added to blocklist"
    end

    test "blocking a topic does not duplicate existing blocklist entry" do
      topic = Topic.create!(name: "Duplicate Entry", status: "proposed", review_status: "proposed")
      TopicBlocklist.create!(name: "duplicate entry")

      assert_no_difference "TopicBlocklist.count" do
        post block_admin_topic_url(topic)
      end
    end

    test "should mark approved topic as needs review" do
      assert_difference "TopicReviewEvent.count", 1 do
        post needs_review_admin_topic_url(@approved_topic)
      end

      @approved_topic.reload
      assert_equal "proposed", @approved_topic.status
      assert_equal "proposed", @approved_topic.review_status

      event = TopicReviewEvent.order(:created_at).last
      assert_equal "needs_review", event.action
    end

    test "should bulk approve" do
      topic2 = Topic.create!(name: "Proposed 2", status: "proposed", review_status: "proposed")

      assert_difference "TopicReviewEvent.count", 2 do
        post bulk_update_admin_topics_url, params: {
          topic_ids: [ @proposed_topic.id, topic2.id ],
          reason: "dupe cleanup",
          commit: "Approve Selected"
        }
      end

      @proposed_topic.reload
      topic2.reload

      assert_equal "approved", @proposed_topic.review_status
      assert_equal "approved", topic2.review_status

      assert TopicReviewEvent.where(action: "approved", reason: "dupe cleanup").count >= 2
    end

    test "should bulk block" do
      topic2 = Topic.create!(name: "Proposed 2", status: "proposed", review_status: "proposed")

      assert_difference "TopicReviewEvent.count", 2 do
        post bulk_update_admin_topics_url, params: {
          topic_ids: [ @proposed_topic.id, topic2.id ],
          commit: "Block Selected"
        }
      end

      @proposed_topic.reload
      topic2.reload

      assert_equal "blocked", @proposed_topic.review_status
      assert_equal "blocked", topic2.review_status

      assert TopicReviewEvent.where(action: "blocked").count >= 2
    end

    test "should bulk mark for review" do
      @approved_topic.update!(status: "approved", review_status: "approved")

      assert_difference "TopicReviewEvent.count", 1 do
        post bulk_update_admin_topics_url, params: {
          topic_ids: [ @approved_topic.id ],
          commit: "Mark for Review"
        }
      end

      @approved_topic.reload
      assert_equal "proposed", @approved_topic.review_status
    end

    # --- Task 12: triage actions restored to the inbox row itself ---

    test "each inbox row carries a dom id turbo can replace" do
      topic = proposed_topic
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id}", count: 1
    end

    test "a proposed topic offers approve and block from the index" do
      topic = proposed_topic
      get admin_topics_url

      assert_select "form[action=?]", approve_admin_topic_path(topic)
      assert_select "form[action=?]", block_admin_topic_path(topic)
    end

    test "an approved topic offers needs-review and block" do
      topic = Topic.create!(name: "approved #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "form[action=?]", needs_review_admin_topic_path(topic)
      assert_select "form[action=?]", block_admin_topic_path(topic)
    end

    test "a blocked topic offers unblock" do
      topic = Topic.create!(name: "blocked #{SecureRandom.hex(4)}", status: "blocked", review_status: "blocked")
      get admin_topics_url

      assert_select "form[action=?]", unblock_admin_topic_path(topic)
    end

    test "every row offers pin or unpin" do
      pinned = Topic.create!(name: "pinned #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", pinned: true)
      unpinned = Topic.create!(name: "unpinned #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "form[action=?]", unpin_admin_topic_path(pinned)
      assert_select "form[action=?]", pin_admin_topic_path(unpinned)
    end

    test "approving actually approves and returns a replaceable row" do
      topic = proposed_topic

      post approve_admin_topic_path(topic), as: :turbo_stream

      assert_response :success
      assert_equal "approved", topic.reload.status
      assert_equal "approved", topic.review_status
      assert_match "turbo-stream", response.media_type
      assert_match "topic_#{topic.id}", response.body,
        "the turbo stream must target the id the index actually rendered"
    end

    test "blocking blocks the topic" do
      topic = proposed_topic
      post block_admin_topic_path(topic), as: :turbo_stream
      assert_equal "blocked", topic.reload.status
    end

    test "pinning pins the topic" do
      topic = Topic.create!(name: "topin #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      post pin_admin_topic_path(topic), as: :turbo_stream
      assert topic.reload.pinned?
    end

    test "row_for builds a row from a topic" do
      topic = proposed_topic
      row = Admin::Topics::InboxQuery.row_for(topic)

      assert_equal topic.id, row.topic_id
      assert_equal topic.name, row.name
      assert_equal "proposed", row.review_status
    end

    # --- Fix round 1: update's turbo_stream branch must match its html
    # sibling's status handling, or an invalid save silently succeeds (200)
    # and renders a row built from the invalid in-memory @topic. ---

    test "updating via turbo_stream on success replaces the row" do
      topic = Topic.create!(name: "valid name #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

      patch admin_topic_path(topic), params: { topic: { description: "A fresh description" } }, as: :turbo_stream

      assert_response :success
      assert_match "turbo-stream", response.media_type
      assert_match "topic_#{topic.id}", response.body
      assert_equal "A fresh description", topic.reload.description
    end

    test "each row has an inline importance editor" do
      topic = Topic.create!(name: "importance #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", importance: 3)
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id} form[action=?]", admin_topic_path(topic) do
        assert_select "input[name='topic[importance]'][value='3']"
      end
    end

    test "importance can be saved from the index" do
      topic = Topic.create!(name: "imp save #{SecureRandom.hex(4)}", status: "approved", review_status: "approved", importance: 1)

      patch admin_topic_path(topic), params: { topic: { importance: 7 } }, as: :turbo_stream

      assert_equal 7, topic.reload.importance
    end

    test "updating via turbo_stream with an invalid name returns unprocessable_entity and does not corrupt the row" do
      original_name = "valid name #{SecureRandom.hex(4)}"
      topic = Topic.create!(name: original_name, status: "approved", review_status: "approved")

      patch admin_topic_path(topic), params: { topic: { name: "" } }, as: :turbo_stream

      assert_response :unprocessable_entity
      assert_equal original_name.downcase, topic.reload.name, "the invalid save must not have persisted"
      assert_no_match ">#{admin_topic_path(topic)}<", response.body,
        "an invalid save must not fall back to rendering the topic's own URL as the row's visible link text"
    end

    # --- Fix round 1: turbo_stream responses render no flash at all, so a
    # rejected save must be visible IN the replaced row itself or it is
    # silent. Proves the error text actually lands in the 422 body, not just
    # the status code. ---

    test "an invalid update renders the validation error text into the replaced row" do
      topic = Topic.create!(name: "valid name #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

      patch admin_topic_path(topic), params: { topic: { name: "" } }, as: :turbo_stream

      assert_response :unprocessable_entity
      assert_match "Name can&#39;t be blank", response.body,
        "the row replacement must surface the validation error, or a rejected save looks identical to a successful one"
    end

    # --- Task 14: harvest the mention-preview expander from the dead
    # _topic.html.erb partial before Task 15 deletes it ---

    test "rows with mentions offer an expandable preview" do
      topic = Topic.create!(name: "mentions #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current,
                                status: "minutes_posted", detail_page_url: "http://example.com/m/#{SecureRandom.hex(6)}")
      item = AgendaItem.create!(meeting: meeting, number: 1, title: "Sidewalk item", order_index: 1)
      AgendaItemTopic.create!(topic: topic, agenda_item: item)

      get admin_topics_url

      assert_select "tbody#topic_#{topic.id}[data-controller='row-toggle']"
      assert_select "tbody#topic_#{topic.id} button[data-action='row-toggle#toggle']"
      assert_select "tbody#topic_#{topic.id} tr[data-row-toggle-target='details'][hidden]"
    end

    test "rows without mentions disable the preview button" do
      topic = Topic.create!(name: "nomentions #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")
      get admin_topics_url

      assert_select "tbody#topic_#{topic.id} button[disabled]"
    end

    test "a row with mentions defers its preview to a lazy turbo-frame" do
      topic = topic_with_mention_and_documents(0)

      get admin_topics_url

      assert_select "tbody#topic_#{topic.id} turbo-frame[loading=lazy]" \
                    "[src=?]", mention_preview_admin_topic_path(topic, preview_window: 160)
      assert_select "tbody#topic_#{topic.id} turbo-frame##{"topic_#{topic.id}_preview_frame"}"
    end

    test "the preview endpoint renders up to three mentions with highlighted terms and a citation" do
      topic = Topic.create!(name: "sidewalk assessment #{SecureRandom.hex(4)}",
                            status: "approved", review_status: "approved")
      4.times do |i|
        meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular",
                                  starts_at: i.days.ago, status: "minutes_posted",
                                  detail_page_url: "http://example.com/m/#{SecureRandom.hex(6)}")
        item = AgendaItem.create!(meeting: meeting, number: 1, title: "Item #{i}", order_index: 1)
        AgendaItemTopic.create!(topic: topic, agenda_item: item)
        document = MeetingDocument.create!(meeting: meeting, document_type: "minutes_pdf",
                                           source_url: "http://example.com/d/#{SecureRandom.hex(6)}")
        Extraction.create!(meeting_document: document, page_number: 7,
                           raw_text: "The council took up #{topic.name} at length.")
      end

      get mention_preview_admin_topic_path(topic)

      assert_response :success
      assert_select "turbo-frame#topic_#{topic.id}_preview_frame", count: 1
      assert_select "turbo-frame .table-desc", { count: 3 },
        "the expander shows the three most recent mentions, not every one"
      assert_select "span.font-bold.italic", { text: topic.name },
        "the matched term must still be highlighted inside the excerpt"
      assert_select "turbo-frame .timestamp", { text: /Minutes pdf · page 7/ },
        "the excerpt must still cite the document and page it came from"
    end

    test "the preview endpoint says so when a topic has no mentions" do
      topic = Topic.create!(name: "quiet #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

      get mention_preview_admin_topic_path(topic)

      assert_response :success
      assert_select "turbo-frame", text: /No recent mentions/
    end

    # --- Final review, M1: the expander must not cost anything until it is
    # expanded. Task 14 called topic_recent_mentions once per row at index
    # render time; that helper eager-loads each linked document's
    # extracted_text and every Extraction row behind it, which measured 23.6s
    # and 733 queries for a 200-row index on the 641-topic development
    # database. The preview now lives behind a lazy <turbo-frame> pointing at
    # #mention_preview, so the index's query count must not grow with the
    # number of rows that have mentions. ---

    def count_index_queries
      count = 0
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        count += 1 unless payload[:name].to_s.in?(%w[SCHEMA TRANSACTION])
      end
      get admin_topics_url
      count
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    def topic_with_mention_and_documents(index)
      topic = Topic.create!(name: "preview cost #{index} #{SecureRandom.hex(4)}",
                            status: "approved", review_status: "approved")
      meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: Time.current,
                                status: "minutes_posted", detail_page_url: "http://example.com/m/#{SecureRandom.hex(6)}")
      item = AgendaItem.create!(meeting: meeting, number: 1, title: "preview cost item", order_index: 1)
      AgendaItemTopic.create!(topic: topic, agenda_item: item)
      document = MeetingDocument.create!(meeting: meeting, document_type: "minutes_pdf",
                                         source_url: "http://example.com/d/#{SecureRandom.hex(6)}",
                                         extracted_text: "preview cost #{index} discussed at length")
      Extraction.create!(meeting_document: document, page_number: 1,
                         raw_text: "preview cost #{index} discussed at length")
      topic
    end

    test "the index issues no per-row mention-preview queries" do
      2.times { |i| topic_with_mention_and_documents(i) }
      baseline = count_index_queries

      10.times { |i| topic_with_mention_and_documents(i + 2) }
      with_ten_more = count_index_queries

      assert_equal baseline, with_ten_more,
        "ten more rows with mentions changed the index's query count from " \
        "#{baseline} to #{with_ten_more} — something is loading preview data " \
        "per row again instead of leaving it to the lazy turbo-frame"

      # An absolute ceiling as well as a constant one: a rewrite that made the
      # per-row work constant-but-huge (one giant join) would satisfy the
      # equality above. Measured on the pre-fix code (Task 14's inline
      # preview), this same setup issued 21 queries for 2 rows and 61 for 12 —
      # so both assertions here fail against it. The fixed index issues 8,
      # regardless of row count.
      assert_operator with_ten_more, :<=, 40,
        "the topic inbox should render from a handful of preloaded queries"
    end

    # --- Task 14: the turbo replacement paths render this partial with only
    # `row:` (and `errors:` on failure) — neither `topic:` nor
    # `preview_window:` is passed. The partial must tolerate their absence. ---

    test "approving via turbo_stream still renders the row without topic or preview_window locals" do
      topic = proposed_topic
      post approve_admin_topic_path(topic), as: :turbo_stream

      assert_response :success
      assert_match "topic_#{topic.id}", response.body
    end

    test "an invalid turbo_stream update still renders the row without topic or preview_window locals" do
      topic = Topic.create!(name: "valid name #{SecureRandom.hex(4)}", status: "approved", review_status: "approved")

      patch admin_topic_path(topic), params: { topic: { name: "" } }, as: :turbo_stream

      assert_response :unprocessable_entity
      assert_match "topic_#{topic.id}", response.body
    end
  end
end
