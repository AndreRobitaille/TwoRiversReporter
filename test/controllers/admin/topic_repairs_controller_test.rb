require "test_helper"

module Admin
  class TopicRepairsControllerTest < ActionDispatch::IntegrationTest
    setup do
      @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
      @admin.ensure_totp_secret!

      post session_url, params: { email_address: @admin.email_address, password: "password" }
      follow_redirect!

      totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
      post mfa_session_url, params: { code: totp.now }
      follow_redirect!

      @topic = Topic.create!(name: "lakeshore community foundation partnership", status: "approved", review_status: "approved")
    end

    test "shows topic repair workspace" do
      get repair_admin_topic_url(@topic, source_topic_id: 123, q: "lakeshore")

      assert_redirected_to admin_topic_url(@topic, source_topic_id: 123, q: "lakeshore")
    end

    test "history endpoint lazily renders recent topic history" do
      TopicReviewEvent.create!(topic: @topic, user: @admin, action: "retired", reason: "cleanup")

      get history_admin_topic_url(@topic)

      assert_response :success
      assert_match '<turbo-frame id="topic-repair-history">', response.body
      assert_match "History", response.body
      assert_match "cleanup", response.body
      assert_match @admin.email_address, response.body
    end

    test "history endpoint shows reasons for non-retired review events" do
      TopicReviewEvent.create!(topic: @topic, user: @admin, action: "alias_removed", reason: "duplicate label")

      get history_admin_topic_url(@topic)

      assert_response :success
      assert_match "Alias removed", response.body
      assert_match "duplicate label", response.body
    end

    test "merge_candidates returns matching topics with reasons" do
      matching = Topic.create!(name: "lakeshore community foundation", status: "approved", description: "Nearby foundation work")
      TopicAlias.create!(topic: matching, name: "lakeshore foundation")

      get merge_candidates_admin_topic_url(@topic), params: { q: "lakeshore" }

      assert_response :success
      assert_match matching.name, response.body
      assert_match "name matches search", response.body
      assert_match "data-action=\"click->topic-detail-impact#selectCandidate\"", response.body
      assert_match "data-topic-mention-count=\"0\"", response.body
      assert_match "data-topic-summary-count=\"0\"", response.body
    end

    test "merge_candidates in merge_away mode wires topic repair selection" do
      matching = Topic.create!(name: "lakeshore community foundation", status: "approved")

      get merge_candidates_admin_topic_url(@topic), params: { q: "lakeshore", mode: "merge_away" }

      assert_response :success
      assert_match matching.name, response.body
      assert_match 'data-action="click->topic-repair-search#selectCandidate"', response.body
      assert_no_match "click->topic-detail-impact#selectCandidate", response.body
    end

    test "impact preview returns compact impact summary for merge workbench" do
      source = Topic.create!(name: "lakeshore community foundation", status: "approved")
      TopicAlias.create!(topic: source, name: "lakeshore foundation")

      get impact_preview_admin_topic_url(@topic), params: { source_topic_id: source.id }

      assert_response :success
      assert_match "Downstream impact", response.body
      assert_match "Topics affected", response.body
      assert_match "Aliases to move", response.body
      assert_match "Appearances/Mentions", response.body
      assert_match "Decisions/Votes", response.body
      assert_match "Knowledge links", response.body
      assert_match "Search, detail pages, summaries, and knowledge-linked content will all point to", response.body
      assert_match "Combining lakeshore community foundation into lakeshore community foundation partnership", response.body
      assert_match "will combine into lakeshore community foundation partnership", response.body
    end

    test "merge modal wiring targets the selected source topic and detail merge path" do
      source = Topic.create!(name: "lakeshore community foundation", status: "approved")
      TopicAlias.create!(topic: source, name: "lakeshore foundation")

      get admin_topic_url(@topic), params: { source_topic_id: source.id, q: "lakeshore" }

      assert_response :success
      assert_match 'data-action="click->topic-detail-impact#openMergeConfirm"', response.body
      assert_match %r{<div id="merge-modal" class="modal" data-controller="modal" hidden>}, response.body
      assert_match %r{<strong data-modal-target="sourceName"></strong>}, response.body
      assert_match %r{<input[^>]*name="source_topic_id"[^>]*data-modal-target="sourceTopicId"[^>]*>}, response.body
      assert_match 'name="source_topic_name"', response.body
      assert_match 'data-topic-detail-impact-target="sourceName"', response.body
      assert_match %r{action="/admin/topics/#{@topic.id}/merge_from_repair"}, response.body
    end

    test "merge from repair workspace allows a blank reason" do
      source = Topic.create!(name: "lakeshore community foundation", status: "approved")

      post merge_from_repair_admin_topic_url(@topic), params: { source_topic_id: source.id, reason: "" }

      assert_redirected_to admin_topic_url(@topic)
      assert_equal "Combined duplicate topic #{source.name} into #{@topic.name}.", flash[:notice]
      assert_not Topic.exists?(source.id)
    end

    test "merge from repair workspace merges the selected topic into the current topic" do
      source = Topic.create!(name: "lakeshore community foundation", status: "approved")
      TopicAlias.create!(topic: source, name: "lakeshore foundation")

      post merge_from_repair_admin_topic_url(@topic), params: { source_topic_id: source.id, reason: "duplicate topic" }

      assert_redirected_to admin_topic_url(@topic)

      assert_nil Topic.find_by(id: source.id)
      assert_includes @topic.reload.topic_aliases.pluck(:name), "lakeshore community foundation"
      assert_equal "duplicate topic", TopicReviewEvent.find_by!(topic: @topic, action: "merged").reason
    end

    test "merge away from repair workspace merges the current topic into the selected destination" do
      destination = Topic.create!(name: "lakeshore district", status: "approved")
      TopicAlias.create!(topic: @topic, name: "lakeshore foundation")

      post merge_away_from_repair_admin_topic_url(@topic), params: { destination_topic_id: destination.id, reason: "canonical correction" }

      assert_redirected_to admin_topic_url(destination)
      assert_nil Topic.find_by(id: @topic.id)
      assert_includes destination.reload.topic_aliases.pluck(:name), "lakeshore community foundation partnership"
      assert_equal "canonical correction", TopicReviewEvent.find_by!(topic: destination, action: "merged").reason
    end

    test "merge away from repair workspace requires a destination topic" do
      post merge_away_from_repair_admin_topic_url(@topic), params: { destination_topic_id: 0, reason: "canonical correction" }

      assert_redirected_to admin_topic_url(@topic)
      assert_equal "Destination topic not found.", flash[:alert]
    end

    test "topic_to_alias moves the topic and its aliases under a destination topic" do
      destination = Topic.create!(name: "lakeshore district", status: "approved", review_status: "approved")
      source = Topic.create!(name: "lakeshore community foundation project", status: "approved", review_status: "approved")
      TopicAlias.create!(topic: source, name: "lakeshore project")
      meeting = Meeting.create!(body_name: "Council", meeting_type: "Regular", starts_at: 1.day.ago, status: "minutes_posted", detail_page_url: "http://example.com")
      agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Project update", order_index: 1)
      AgendaItemTopic.create!(topic: source, agenda_item: agenda_item)
      TopicSummary.create!(topic: source, meeting: meeting, summary_type: "topic_digest", content: "Source topic summary", generation_data: { source: "test" })
      KnowledgeSourceTopic.create!(knowledge_source: KnowledgeSource.create!(title: "report", source_type: "note", origin: "manual", status: "approved"), topic: source)

      TopicAlias.create!(topic: destination, name: "district alias")

      get impact_preview_admin_topic_url(source), params: { action_name: "topic_to_alias", target_topic_id: destination.id, alias_count: 1 }

      assert_response :success
      assert_match "lakeshore community foundation project will stop being a standalone topic and become an alias of lakeshore district.", response.body
      assert_match "This will move 1 existing alias plus the current topic name under lakeshore district.", response.body
      assert_match %r{<dt class="text-secondary">Appearances/Mentions</dt><dd>1</dd>}, response.body
      assert_match %r{<dt class="text-secondary">Aliases to move</dt><dd>1</dd>}, response.body
      assert_match %r{<dt class="text-secondary">Summaries</dt><dd>1</dd>}, response.body
      assert_match %r{<dt class="text-secondary">Knowledge links</dt><dd>1</dd>}, response.body

      post topic_to_alias_admin_topic_url(source), params: { destination_topic_id: destination.id, reason: "wrong main topic" }

      assert_redirected_to admin_topic_url(destination)
      assert_includes destination.reload.topic_aliases.pluck(:name), "lakeshore community foundation project"
      assert_includes destination.topic_aliases.pluck(:name), "lakeshore project"
    end

    test "flip alias swaps the topic name with its only alias" do
      topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
      TopicAlias.create!(topic: topic, name: "harbor project")

      post flip_alias_admin_topic_url(topic), params: { q: "harbor", source_topic_id: 42 }

      assert_redirected_to admin_topic_url(topic, q: "harbor", source_topic_id: 42)
      assert_nil flash[:alert]
      flipped = Topic.find(topic.id)
      assert_equal "harbor project", flipped.name
      assert_equal [ "harbor dredging" ], flipped.topic_aliases.order(:name).pluck(:name)
      assert_equal 1, TopicReviewEvent.where(topic: flipped, action: "alias_flipped").count
    end

    test "merge from repair workspace redirects back when source topic is missing" do
      missing_id = Topic.maximum(:id).to_i + 1

      post merge_from_repair_admin_topic_url(@topic), params: { source_topic_id: missing_id, reason: "duplicate topic" }

      assert_redirected_to admin_topic_url(@topic, source_topic_id: missing_id)
      assert_equal "Duplicate topic not found.", flash[:alert]
    end

    test "impact preview includes knowledge link impact" do
      source = Topic.create!(name: "lakeshore community foundation", status: "approved")
      knowledge_source = KnowledgeSource.create!(title: "report", source_type: "note", origin: "manual", status: "approved")
      KnowledgeSourceTopic.create!(knowledge_source: knowledge_source, topic: source)

      get impact_preview_admin_topic_url(@topic), params: { source_topic_id: source.id }

      assert_response :success
      assert_match "Knowledge links", response.body
      assert_match "knowledge links", response.body
    end

    test "impact preview supports retire language" do
      get impact_preview_admin_topic_url(@topic), params: { action_name: "retire" }

      assert_response :success
      assert_match "Retiring this topic will block future reuse", response.body
      assert_match "This topic will be blocked from future reuse and discovery.", response.body
    end

    test "impact preview supports move alias language" do
      target = Topic.create!(name: "lakeshore district", status: "approved")
      TopicAlias.create!(topic: target, name: "district alias")

      get impact_preview_admin_topic_url(@topic), params: { action_name: "move_alias", alias_name: "lakeshore partners", alias_count: 1, target_topic_id: target.id }

      assert_response :success
      assert_match "Moving lakeshore partners to lakeshore district", response.body
      assert_match "will transfer 1 alias entry and leave 1 alias already on the destination topic", response.body
      assert_match target.name, response.body
      assert_match "Aliases moving", response.body
      assert_match "Destination aliases already there", response.body
    end

    test "impact preview uses supplied alias count for merge away" do
      destination = Topic.create!(name: "lakeshore district", status: "approved")
      TopicAlias.create!(topic: @topic, name: "lakeshore foundation")
      TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      get impact_preview_admin_topic_url(@topic), params: { action_name: "merge_away", target_topic_id: destination.id, alias_count: 2 }

      assert_response :success
      assert_match "will update 0 pages/mentions, 3 aliases", response.body
    end

    test "impact preview for merge away uses the current topic as the moving source" do
      destination = Topic.create!(name: "lakeshore district", status: "approved")
      Meeting.create!(body_name: "Council", meeting_type: "Regular", starts_at: 1.day.ago, status: "minutes_posted", detail_page_url: "http://example.com")

      get impact_preview_admin_topic_url(@topic), params: { action_name: "merge_away", target_topic_id: destination.id }

      assert_response :success
      assert_match "Moving #{@topic.name} under #{destination.name}", response.body
      assert_match "Topics affected", response.body
      assert_match "will update 0 pages/mentions", response.body
    end

    test "move alias form preserves search context through selection and submit" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      get admin_topic_url(@topic, q: "lakeshore", source_topic_id: 55)

      assert_response :success
      assert_match 'name="q"', response.body
      assert_match 'value="lakeshore"', response.body
      assert_match 'name="source_topic_id"', response.body
      assert_match 'value="55"', response.body
      assert_match 'data-topic-repair-search-target="preview"', response.body
      assert_match "Choose a destination topic to preview the move.", response.body
      assert_match alias_record.name, response.body
    end

    test "move alias under another topic transfers the alias to the target topic" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partners")
      target = Topic.create!(name: "lakeshore district", status: "approved")

      post move_alias_admin_topic_url(@topic), params: { alias_id: alias_record.id, target_topic_id: target.id, reason: "move alias under another topic" }

      assert_redirected_to admin_topic_url(@topic)
      assert_equal target, alias_record.reload.topic
      assert_equal "move alias under another topic", TopicReviewEvent.find_by!(action: "alias_moved").reason
    end

    test "move alias form includes preserved merge context fields" do
      TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      get admin_topic_url(@topic, q: "lakeshore", source_topic_id: 55)

      assert_response :success
      assert_match 'name="q"', response.body
      assert_match 'value="lakeshore"', response.body
      assert_match 'name="source_topic_id"', response.body
      assert_match 'value="55"', response.body
    end

    test "removes alias from repair workspace" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partnership")

      delete remove_alias_admin_topic_url(@topic), params: { alias_id: alias_record.id, reason: "duplicate alias", source_topic_id: 55, q: "lakeshore" }

      assert_redirected_to admin_topic_url(@topic, source_topic_id: 55, q: "lakeshore")
      assert_not TopicAlias.exists?(alias_record.id)
      assert_equal "duplicate alias", TopicReviewEvent.find_by!(action: "alias_removed").reason
    end

    test "promote alias keeps the supplied reason" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      post promote_alias_admin_topic_url(@topic), params: { alias_id: alias_record.id, reason: "alias should stand alone", source_topic_id: 55 }

      promoted = Topic.find_by(name: "lakeshore partners")

      assert_redirected_to admin_topic_url(promoted, source_topic_id: @topic.id, source_topic_name: @topic.name, q: @topic.name)
      assert_equal "alias should stand alone", TopicReviewEvent.find_by!(action: "alias_promoted").reason
    end

    test "promotes alias from repair workspace into a new topic" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      assert_difference -> { Topic.count }, 1 do
        post promote_alias_admin_topic_url(@topic), params: { alias_id: alias_record.id }
      end

      promoted = Topic.find_by(name: "lakeshore partners")

      assert_redirected_to admin_topic_url(promoted, source_topic_id: @topic.id, source_topic_name: @topic.name, q: @topic.name)
      assert_not_nil promoted
      assert_not TopicAlias.exists?(alias_record.id)
      assert_equal promoted, TopicReviewEvent.find_by!(action: "alias_promoted").topic
    end

    test "promote alias redirect preserves the source topic name for merge follow-up" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      post promote_alias_admin_topic_url(@topic), params: { alias_id: alias_record.id }

      assert_redirected_to admin_topic_url(Topic.find_by(name: "lakeshore partners"), source_topic_id: @topic.id, source_topic_name: @topic.name, q: @topic.name)
    end

    test "move alias form keeps the controller scope around selection and submit state" do
      alias_record = TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      get admin_topic_url(@topic)

      assert_response :success
      assert_match 'data-controller="topic-repair-search"', response.body
      assert_match "data-topic-repair-search-target=\"targetId\"", response.body
      assert_match "name=\"alias_name\"", response.body
      assert_match "data-topic-repair-search-target=\"preview\"", response.body
      assert_match "data-topic-repair-search-target=\"submit\"", response.body
      assert_match alias_record.name, response.body
    end

    test "canonical correction includes topic-to-alias controls" do
      TopicAlias.create!(topic: @topic, name: "lakeshore partners")
      matching = Topic.create!(name: "lakeshore district", status: "approved", review_status: "approved")

      get merge_candidates_admin_topic_url(@topic), params: { q: "lakeshore", mode: "topic_to_alias" }

      assert_response :success
      assert_match matching.name, response.body
      assert_match 'data-action="click->topic-repair-search#selectCandidate"', response.body
    end

    test "canonical correction shows topic-to-alias warning and action copy" do
      TopicAlias.create!(topic: @topic, name: "lakeshore partners")

      get admin_topic_url(@topic)

      assert_response :success
      assert_match "This Topic Is Wrong", response.body
      assert_match "Make This Topic An Alias Of Another Topic", response.body
      assert_match "any existing aliases on this topic move with it to the new canonical destination", response.body
      assert_no_match "Canonical Correction", response.body
      assert_no_match "Confirm merge", response.body
    end
  end
end
