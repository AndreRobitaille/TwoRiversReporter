require "test_helper"

class Topics::ResidentImpactPolicyTest < ActiveSupport::TestCase
  setup do
    @topic = Topic.create!(name: "sex offender residency restrictions", status: "approved")
  end

  test "individual appeal stays substantive even when AI rates it procedural" do
    link_item("Consider an appeal from sex-offender residency restrictions")

    @topic.update_resident_impact_from_ai(1)

    assert_equal 3, @topic.reload.resident_impact_score
  end

  test "citywide ordinance amendment has substantial impact without a divided vote" do
    link_item("An Ordinance Amending Sex Offender Residency Restrictions")

    @topic.update_resident_impact_from_ai(2)

    assert_equal 4, @topic.reload.resident_impact_score
  end

  test "replacement of citywide prohibition survives scoring an older individual appeal" do
    law = link_item("26-176 An Ordinance Regarding Sex Offender Residency Restrictions, to Replace the Citywide Residency Prohibition with a 1,000-foot Protected-location Restriction", at: 2.days.from_now)
    link_item("Consider an individual sex-offender residency appeal", at: 6.months.ago)

    @topic.update_resident_impact_from_ai(5)
    @topic.update_resident_impact_from_ai(1)

    assert_equal 5, @topic.reload.resident_impact_score
    assert_equal 2.days.from_now.to_date, law.meeting.starts_at.to_date
  end

  test "historical legislation does not permanently force a top-story rating" do
    link_item("An Ordinance to Replace the Citywide Sex Offender Residency Ban", at: 31.days.ago)
    link_item("Consider a sex-offender residency appeal")

    @topic.update_resident_impact_from_ai(2)

    assert_equal 3, @topic.reload.resident_impact_score
  end

  test "cancelled legislation does not elevate an individual appeal" do
    link_item("An Ordinance to Replace the Citywide Sex Offender Residency Ban", status: "cancelled")
    link_item("Consider a sex-offender residency appeal")

    @topic.update_resident_impact_from_ai(2)

    assert_equal 3, @topic.reload.resident_impact_score
  end

  test "an individual appeal seeking an amendment is not a citywide rewrite" do
    link_item("Consider an Appeal Requesting an Amendment to Sex Offender Residency Ordinance")

    @topic.update_resident_impact_from_ai(2)

    assert_equal 3, @topic.reload.resident_impact_score
  end

  test "unrelated linked ordinances do not elevate the sex-offender topic" do
    link_item("An Ordinance Amending Citywide Parking Restrictions")
    link_item("Consider a sex-offender residency appeal")

    @topic.update_resident_impact_from_ai(1)

    assert_equal 3, @topic.reload.resident_impact_score
  end

  test "a broad topic name can be recognized through its substantive agenda evidence" do
    @topic.update!(name: "residency appeals")
    link_item("An Ordinance Revising Sex Offender Residency Restrictions")

    @topic.update_resident_impact_from_ai(1)

    assert_equal 4, @topic.reload.resident_impact_score
  end

  test "routine topics retain their AI score" do
    @topic.update!(name: "urban forestry")
    link_item("Authorize an urban forestry grant application")

    @topic.update_resident_impact_from_ai(2)

    assert_equal 2, @topic.reload.resident_impact_score
  end

  test "a structural heading cannot establish a policy rating" do
    link_item("Sex Offender Residency Ordinance Amendment", kind: "section")

    @topic.update_resident_impact_from_ai(1)

    assert_equal 3, @topic.reload.resident_impact_score
  end

  test "admin rating overrides remain authoritative even for stale job objects" do
    link_item("An Ordinance to Replace the Citywide Sex Offender Residency Ban")
    stale_topic = Topic.find(@topic.id)
    @topic.update!(resident_impact_score: 2, resident_impact_overridden_at: Time.current)

    stale_topic.update_resident_impact_from_ai(5)
    stale_topic.refresh_resident_impact_priority

    assert_equal 2, @topic.reload.resident_impact_score
  end

  test "refresh supplies missing priority without lowering a higher rating" do
    link_item("Consider a sex-offender residency appeal")
    assert_nil @topic.resident_impact_score

    @topic.refresh_resident_impact_priority
    assert_equal 3, @topic.reload.resident_impact_score

    @topic.update!(resident_impact_score: 5)
    @topic.refresh_resident_impact_priority
    assert_equal 5, @topic.reload.resident_impact_score
  end

  private

  def link_item(title, at: Time.current, status: "upcoming", kind: "item")
    meeting = Meeting.create!(body_name: "City Council", starts_at: at, status: status, detail_page_url: "http://example.com/impact-#{SecureRandom.hex(6)}")
    item = meeting.agenda_items.create!(title: title, kind: kind)
    AgendaItemTopic.create!(agenda_item: item, topic: @topic)
    item
  end
end
