require "test_helper"

class AdminTopicDetailWorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@example.com", password: "password", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!

    post session_url, params: { email_address: @admin.email_address, password: "password" }
    follow_redirect!

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect!
  end

  test "shows repair-first detail workspace shell" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "This Topic Is Correct", response.body
    assert_match "This Topic Is Wrong", response.body
    assert_match "Aliases On This Topic", response.body
    assert_match "This Topic Should Not Exist", response.body
    assert_match 'data-controller="topic-decision-board topic-detail-impact"', response.body
    assert_match 'data-topic-decision-board-target="card" data-expanded="true"', response.body
    assert_match 'data-topic-decision-board-target="card" data-expanded="false"', response.body
    assert_no_match "Merge Into This Topic", response.body
    assert_no_match "Alias Repair", response.body
    assert_no_match "Canonical Correction", response.body
    assert_no_match "Confirm merge", response.body
    assert_match "Combine Duplicate Topic", response.body
    assert_match "Edit details", response.body
    assert_match "data-details-collapsible", response.body
    assert_match 'name="topic[name]"', response.body
    assert_match 'name="topic[description]"', response.body
    assert_match 'name="topic[source_type]"', response.body
    assert_match 'name="topic[source_notes]"', response.body
    assert_match 'name="topic[importance]"', response.body
    assert_match 'name="topic[resident_impact_score]"', response.body
    assert_match "Save details", response.body
  end

  test "shows topic detail as a decision board" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic)

    assert_response :success
    assert_match /This Topic Is Correct.*This Topic Is Wrong.*Aliases On This Topic.*This Topic Should Not Exist/m, response.body
    assert_match 'data-controller="topic-decision-board topic-detail-impact"', response.body
    assert_no_match "Merge Into This Topic", response.body
    assert_no_match "Canonical Correction", response.body
    assert_no_match "Alias Repair", response.body
    assert_no_match "Confirm merge", response.body
  end

  test "shows merge workbench with impact preview language" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    source = Topic.create!(name: "harbor project", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: source, name: "dredging project")

    get admin_topic_url(topic), params: { source_topic_id: source.id }

    assert_response :success
    assert_match "This Topic Is Correct", response.body
    assert_match "Another topic is the same issue and should live under this topic", response.body
    assert_match "Find source topic", response.body
    assert_match "Selected topic ID", response.body
    assert_match "Downstream impact", response.body
    assert_match "Topics affected", response.body
    assert_match "Search, detail pages, summaries, and knowledge-linked content will all point to", response.body
    assert_match "Combine Duplicate Topic Here", response.body
    assert_match 'data-action="click->topic-detail-impact#openMergeConfirm"', response.body
    assert_match 'name="source_topic_name"', response.body
    assert_match 'name="source_topic_id"', response.body
    assert_match '/merge_from_repair"', response.body
    assert_match %r{action="/admin/topics/#{topic.id}/merge_from_repair"}, response.body
    assert_match %r{data-topic-detail-impact-url-value="/admin/topics/#{topic.id}/impact_preview"}, response.body
    assert_no_match "http://www.example.com/admin/topics/#{topic.id}/impact_preview", response.body
    assert_no_match "Merge Into This Topic", response.body
    assert_no_match "Confirm merge", response.body
  end

  test "merge workbench is not actionable until a source topic is selected" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "Combine Duplicate Topic Here", response.body
    assert_match "Choose a topic from search results.", response.body
  end

  test "alias repair forms carry merge context fields" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic), params: { source_topic_id: 123, q: "harbor" }

    assert_response :success
    assert_match 'name="q"', response.body
    assert_match 'value="harbor"', response.body
    assert_match 'name="source_topic_id"', response.body
    assert_match 'value="123"', response.body
  end

  test "move alias preview starts blank until destination is selected" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "Choose a destination topic to preview the move.", response.body
    assert_no_match "will transfer 1 alias entry", response.body
  end

  test "topic-to-alias card does not self-target" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "Make This Topic An Alias Of Another Topic", response.body
    assert_no_match "destination_topic_id=#{topic.id}", response.body
  end

  test "topic-to-alias preview starts blank until destination is selected" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")
    destination = Topic.create!(name: "harbor project", status: "approved", review_status: "approved")

    get admin_topic_url(topic), params: { source_topic_id: destination.id }

    assert_response :success
    assert_match "This Topic Is Wrong", response.body
    assert_match 'data-topic-repair-search-action-name-value="topic_to_alias"', response.body
    assert_match "Choose a destination topic to preview the alias transfer.", response.body
    assert_match "Any existing aliases on this topic will move with it.", response.body
    assert_match 'name="reason"', response.body
    assert_match 'required="required"', response.body
    assert_match 'name="alias_count"', response.body
    assert_match 'value="1"', response.body
    assert_match 'data-controller="topic-repair-search"', response.body
    assert_match 'data-topic-repair-search-url-value="/admin/topics/', response.body
    assert_match "mode=topic_to_alias", response.body
    assert_match 'data-action="input->topic-repair-search#search"', response.body
  end

  test "shows flip alias action only when the topic has exactly one alias" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "Flip Main Topic With Its Only Alias", response.body

    other_topic = Topic.create!(name: "harbor district", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: other_topic, name: "harbor works")
    TopicAlias.create!(topic: other_topic, name: "harbor district alt")

    get admin_topic_url(other_topic)

    assert_response :success
    assert_no_match "Flip Main Topic With Its Only Alias", response.body
  end

  test "canonical re-home preview uses the current topic alias count" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")
    TopicAlias.create!(topic: topic, name: "harbor works")
    destination = Topic.create!(name: "harbor district", status: "approved", review_status: "approved")

    get admin_topic_url(topic), params: { source_topic_id: destination.id }

    assert_response :success
    assert_match 'name="alias_count"', response.body
    assert_match 'value="2"', response.body
  end

  test "shows topic-level aliasing card with alias-transfer warning" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "This Topic Is Wrong", response.body
    assert_match "Make This Topic An Alias Of Another Topic", response.body
    assert_match "Any existing aliases on this topic will move with it", response.body
    assert_no_match "Canonical Correction", response.body
  end

  test "shows retire block affordance on the detail workspace" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 2.days.ago, status: "minutes_posted", detail_page_url: "http://example.com/meeting/retire-preview")
    agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Dredging contract", order_index: 1)
    AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)

    get admin_topic_url(topic)

    assert_response :success
    assert_match "Destructive actions", response.body
    assert_match "Retire / Block Topic", response.body
    assert_match "Block or retire this topic only when it should no longer be usable.", response.body
    assert_match "Consequence preview", response.body
    assert_match "1 appearance", response.body
    assert_match "1 agenda item", response.body
    assert_match "0 decision", response.body
    assert_match "0 summary", response.body
    assert_match "recent review event", response.body
    assert_match "re-home there first", response.body
    assert_match %r{action="/admin/topics/#{topic.id}/retire"}, response.body
    assert_match 'name="reason"', response.body
    assert_match 'data-action="click->topic-detail-impact#openRetireConfirm"', response.body
  end

  test "alias repair shows confirmation language for destructive actions" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    TopicAlias.create!(topic: topic, name: "harbor project")

    get admin_topic_url(topic)

    assert_response :success
    assert_match 'data-controller="topic-decision-board topic-detail-impact"', response.body
    assert_match 'data-action="click->topic-decision-board#toggle"', response.body
    assert_match 'data-topic-decision-board-target="card" data-expanded="true"', response.body
    assert_match 'data-topic-decision-board-target="card" data-expanded="false"', response.body
    assert_match 'aria-expanded="true"', response.body
    assert_match 'aria-expanded="false"', response.body
    assert_match "hidden", response.body
    assert_match "Leave As Alias", response.body
    assert_match "Remove Alias", response.body
    assert_match "Move Alias To Another Topic", response.body
    assert_match "Promote Alias To Its Own Topic", response.body
    assert_match "Remove harbor project?", response.body
    assert_match "1 alias entry from this topic", response.body
    assert_match "Appearances", response.body
    assert_match "Knowledge links", response.body
    assert_match "Promote harbor project?", response.body
    assert_match "new standalone topic shell", response.body
    assert_match %r{<span class="topic-decision-card__chevron"[^>]*>Collapse</span>}, response.body
    assert_match %r{<span class="topic-decision-card__chevron"[^>]*>Expand</span>}, response.body
  end

  test "topic-to-alias card shows the destination flow without self-target" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")

    get admin_topic_url(topic)

    assert_response :success
    assert_match "This Topic Is Wrong", response.body
    assert_match "Make This Topic An Alias Of Another Topic", response.body
    assert_no_match "destination_topic_id=#{topic.id}", response.body
    assert_no_match "Promote to topic", response.body
    assert_no_match "Move alias under another topic", response.body
  end

  test "retire confirmation uses current topic identity" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 2.days.ago, status: "minutes_posted", detail_page_url: "http://example.com/meeting/retire-preview")
    agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Dredging contract", order_index: 1)
    AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)

    get admin_topic_url(topic)

    assert_response :success
    assert_match %Q(data-topic-id="#{topic.id}"), response.body
    assert_match %Q(data-topic-name="#{topic.name}"), response.body
    assert_match "1 appearance", response.body
    assert_match "1 agenda item", response.body
  end

  test "shows visible flash feedback on update failure" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")

    patch admin_topic_url(topic), params: { topic: { name: "" } }

    assert_response :unprocessable_entity
    assert_match "flash", response.body
    assert_match "open", response.body
    assert_match 'name="topic[name]"', response.body
  end

  test "evidence snapshot links back to the meeting" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")
    meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 2.days.ago, status: "minutes_posted", detail_page_url: "http://example.com/meeting/evidence-link")
    agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Dredging contract", order_index: 1)
    AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)

    get admin_topic_url(topic)

    assert_response :success
    assert_match %r{href="/meetings/#{meeting.id}"}, response.body
    assert_match "City Council", response.body
  end

  test "evidence snapshot falls back to agenda item summary when document preview is unavailable" do
    topic = Topic.create!(name: "short term rentals", status: "approved", review_status: "approved")
    meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 2.days.ago, status: "minutes_posted", detail_page_url: "http://example.com/meeting/evidence-summary")
    agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Fee Ordinance", order_index: 1, summary: "This item raises short-term rental license fees and updates the broader fee schedule.")
    AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)

    get admin_topic_url(topic)

    assert_response :success
    assert_match "This item raises short-term rental license fees", response.body
    assert_no_match "Preview unavailable.", response.body
  end

  test "evidence snapshot falls back to labeled topic digest when agenda item summary is unavailable" do
    topic = Topic.create!(name: "short term rentals", status: "approved", review_status: "approved")
    meeting = Meeting.create!(body_name: "City Council", meeting_type: "Regular", starts_at: 2.days.ago, status: "minutes_posted", detail_page_url: "http://example.com/meeting/topic-digest")
    agenda_item = AgendaItem.create!(meeting: meeting, number: "1", title: "Tourism Director Joe Metzen", order_index: 1)
    AgendaItemTopic.create!(topic: topic, agenda_item: agenda_item)
    TopicSummary.create!(topic: topic, meeting: meeting, summary_type: "topic_digest", content: "Tourism staff reported room tax revenue finished about 10% lower than 2024.", generation_data: { source: "test" })

    get admin_topic_url(topic)

    assert_response :success
    assert_match "Topic digest", response.body
    assert_match "Tourism staff reported room tax revenue finished about 10% lower than 2024.", response.body
    assert_no_match "Preview unavailable.", response.body
  end

  test "merge workbench keeps a single reason field in the confirmation modal" do
    topic = Topic.create!(name: "harbor dredging", status: "approved", review_status: "approved")

    get admin_topic_url(topic)

    assert_response :success
    assert_no_match '<label class="block mt-4 mb-2">Reason</label>', response.body
    assert_match 'id="merge-confirm-reason"', response.body
    assert_no_match %r{<textarea[^>]*id="merge-confirm-reason"[^>]*required="required"}, response.body
    assert_match %r{<form[^>]*data-controller="form-feedback"}, response.body
    assert_match %r{data-action="[^"]*form-feedback#submit[^"]*form-feedback#end}, response.body
    assert_match %r{<div id="merge-modal" class="modal" data-controller="modal" hidden>}, response.body
    assert_match %r{<input[^>]*name="source_topic_id"[^>]*data-modal-target="sourceTopicId"[^>]*>}, response.body
    assert_match %r{<strong data-modal-target="sourceName"></strong>}, response.body
  end
end
