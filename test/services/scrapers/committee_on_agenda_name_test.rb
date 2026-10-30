require "test_helper"
require Rails.root.join("db/migrate/20261030124500_rename_committee_on_agenda_to_committee_on_aging.rb")

class Scrapers::CommitteeOnAgendaNameTest < ActiveJob::TestCase
  test "bc-coa discovery stores Committee on Aging and reuses a mislabeled meeting" do
    committee = Committee.create!(name: "Committee on Aging")
    starts_at = Time.zone.parse("2026-11-02 08:30:00")
    existing = Meeting.create!(
      body_name: "Committee On Agenda",
      meeting_type: "regular",
      starts_at: starts_at,
      status: "upcoming",
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda"
    )
    topic = Topic.create!(name: "Senior center check-ins", status: "approved")
    item = existing.agenda_items.create!(title: "Senior Center report", order_index: 1)
    link = AgendaItemTopic.create!(agenda_item: item, topic: topic)
    appearance = TopicAppearance.find_by!(agenda_item: item, topic: topic)
    clear_enqueued_jobs

    job = Scrapers::DiscoverMeetingsJob.new
    row = listing_row(starts_at, "Committee On Agenda", "/bc-coa/page/committee-agenda")

    assert_no_difference "Meeting.count" do
      assert_no_enqueued_jobs do
        assert_equal existing.id, job.send(:process_row, row, 1.day.ago, enqueue_parse_jobs: false)
        assert_equal existing.id, job.send(:process_row, row, 1.day.ago, enqueue_parse_jobs: false)
      end
    end

    existing.reload
    assert_equal "Committee on Aging", existing.body_name
    assert_equal committee.id, existing.committee_id
    assert_equal "/meetings/#{existing.id}", routes.meeting_path(existing)
    assert_equal "committee-on-aging", committee.reload.slug
    assert_equal link.id, AgendaItemTopic.find_by!(agenda_item_id: item.id, topic_id: topic.id).id
    assert_equal topic.id, appearance.reload.topic_id
    assert_equal existing.id, appearance.meeting_id
  end

  test "discovery leaves other bodies and real Committee On Aging titles alone" do
    starts_at = Time.zone.parse("2026-11-09 17:30:00")
    job = Scrapers::DiscoverMeetingsJob.new

    assert_no_enqueued_jobs do
      plan_id = job.send(:process_row, listing_row(starts_at, "Plan Commission Meeting", "/bc-pc/page/plan-commission-meeting-9"), since, enqueue_parse_jobs: false)
      aging_id = job.send(:process_row, listing_row(Time.zone.parse("2026-10-05 08:30:00"), "Committee On Aging", "/bc-coa/page/committee-aging-35"), since, enqueue_parse_jobs: false)
      other_id = job.send(:process_row, listing_row(Time.zone.parse("2026-11-04 10:00:00"), "Committee On Agenda", "/bc-other/page/not-aging"), since, enqueue_parse_jobs: false)
      canceled_id = job.send(:process_row, listing_row(Time.zone.parse("2026-07-06 08:30:00"), "Committee On Agenda - CANCELED", "/bc-coa/page/committee-agenda-canceled"), since, enqueue_parse_jobs: false)

      assert_equal "Plan Commission Meeting", Meeting.find(plan_id).body_name
      assert_equal "Committee On Aging", Meeting.find(aging_id).body_name
      assert_equal "Committee On Agenda", Meeting.find(other_id).body_name
      canceled = Meeting.find(canceled_id)
      assert_equal "Committee on Aging - CANCELED", canceled.body_name
      assert_equal "cancelled", canceled.status
    end
  end

  test "migration renames Committee On Agenda rows without jobs, url changes, or topic link changes" do
    committee = Committee.create!(name: "Committee on Aging")
    bad = Committee.create!(name: "Committee On Agenda")
    assert_equal "committee-on-agenda", bad.slug
    member = Member.create!(name: "Pat Senior")
    membership = CommitteeMembership.create!(committee: bad, member: member, source: "admin_manual", role: "member")
    starts_at = Time.zone.parse("2026-11-02 08:30:00")
    meeting = Meeting.create!(
      body_name: "Committee On Agenda",
      starts_at: starts_at,
      status: "upcoming",
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda",
      committee: bad
    )
    kept = Meeting.create!(
      body_name: "Committee On Aging",
      starts_at: Time.zone.parse("2026-10-05 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-aging-35",
      committee: committee
    )
    other = Meeting.create!(
      body_name: "Plan Commission Meeting",
      starts_at: Time.zone.parse("2026-11-02 17:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-pc/page/plan-commission-meeting-1"
    )
    topic = Topic.create!(name: "Senior center staffing", status: "approved")
    item = meeting.agenda_items.create!(title: "Senior Center report", order_index: 1)
    link = AgendaItemTopic.create!(agenda_item: item, topic: topic)
    appearance = TopicAppearance.find_by!(agenda_item: item, topic: topic)
    topic_slug = topic.slug
    clear_enqueued_jobs

    assert_no_enqueued_jobs { run_correction }

    assert_equal "Committee on Aging", meeting.reload.body_name
    assert_equal committee.id, meeting.committee_id
    assert_equal "/meetings/#{meeting.id}", routes.meeting_path(meeting)
    assert_equal "committee-on-aging", committee.reload.slug
    assert_equal "/committees/#{committee.slug}", routes.committee_path(committee.slug)
    assert_nil Committee.find_by(id: bad.id)
    assert_equal committee.id, membership.reload.committee_id
    assert_equal "/committees/committee-on-aging", Redirect.find_by!(source_path: "/committees/committee-on-agenda").destination
    assert_equal "Committee on Aging", appearance.reload.body_name
    assert_equal committee.id, appearance.committee_id
    assert_equal topic.id, appearance.topic_id
    assert_equal meeting.id, appearance.meeting_id
    assert_equal item.id, appearance.agenda_item_id
    assert_equal link.id, AgendaItemTopic.find(link.id).id
    assert_equal topic_slug, topic.reload.slug
    assert_equal "Committee On Aging", kept.reload.body_name
    assert_equal committee.id, kept.committee_id
    assert_equal "Plan Commission Meeting", other.reload.body_name
    assert_nil other.committee_id
    assert_equal committee, Committee.resolve("Committee On Agenda")

    assert_no_enqueued_jobs { run_correction }
    assert_equal "Committee on Aging", meeting.reload.body_name
    assert_equal 1, Committee.where(name: "Committee on Aging").count
  end

  test "renaming the only mislabeled committee keeps its slug" do
    bad = Committee.create!(name: "Committee On Agenda")
    meeting = Meeting.create!(
      body_name: "Committee On Agenda Meeting",
      starts_at: Time.zone.parse("2026-08-03 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda",
      committee: bad
    )

    assert_no_enqueued_jobs { run_correction }

    bad.reload
    assert_equal "Committee on Aging", bad.name
    assert_equal "committee-on-agenda", bad.slug
    assert_equal "/committees/committee-on-agenda", routes.committee_path(bad.slug)
    assert_equal "Committee on Aging Meeting", meeting.reload.body_name
    assert_equal bad.id, meeting.committee_id
    assert_nil Redirect.find_by(source_path: "/committees/committee-on-agenda")
  end

  private

  def run_correction
    migration = ::RenameCommitteeOnAgendaToCommitteeOnAging.new
    migration.verbose = false
    migration.up
  end

  def since
    Time.zone.parse("2020-01-01")
  end

  def listing_row(starts_at, title, href)
    Nokogiri::HTML.fragment(<<~HTML).at("tr")
      <tr>
        <td class="views-field-field-calendar-date"><span content="#{starts_at.iso8601}"></span></td>
        <td class="views-field-title">#{title}</td>
        <td class="views-field-view-node"><a href="#{href}">View Details</a></td>
      </tr>
    HTML
  end

  def routes
    Rails.application.routes.url_helpers
  end
end
