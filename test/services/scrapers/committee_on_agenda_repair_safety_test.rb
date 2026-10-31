require "test_helper"
require Rails.root.join("db/migrate/20261030124500_rename_committee_on_agenda_to_committee_on_aging.rb")

class Scrapers::CommitteeOnAgendaRepairSafetyTest < ActiveJob::TestCase
  test "bc-coa discovery preserves an unrelated same-time Committee On Agenda meeting" do
    Committee.create!(name: "Committee on Aging")
    other = Committee.create!(name: "Unrelated Board")
    starts_at = Time.zone.parse("2026-11-02 08:30:00")
    existing = Meeting.create!(body_name: "Committee On Agenda", starts_at: starts_at,
      committee: other, detail_page_url: "https://www.two-rivers.org/bc-other/page/not-aging")
    row = Nokogiri::HTML.fragment(<<~HTML).at("tr")
      <tr>
        <td class="views-field-field-calendar-date"><span content="#{starts_at.iso8601}"></span></td>
        <td class="views-field-title">Committee On Agenda</td>
        <td class="views-field-view-node"><a href="/bc-coa/page/committee-agenda">View Details</a></td>
      </tr>
    HTML
    Scrapers::DiscoverMeetingsJob.new.send(:process_row, row, Time.zone.parse("2020-01-01"), enqueue_parse_jobs: false)
    assert_equal "Committee On Agenda", existing.reload.body_name,
      "unrelated meeting body must survive the bc-coa correction"
    assert_equal other.id, existing.committee_id
    assert_equal "https://www.two-rivers.org/bc-other/page/not-aging", existing.detail_page_url
    assert_equal 2, Meeting.where(starts_at: starts_at).count
  end

  test "migration preserves an unrelated Committee On Agenda committee when no Aging committee exists" do
    other = Committee.create!(name: "Committee On Agenda")
    existing = Meeting.create!(body_name: "Committee On Agenda", committee: other,
      starts_at: Time.zone.parse("2026-11-04 10:00:00"),
      detail_page_url: "https://www.two-rivers.org/bc-other/page/not-aging")
    run_correction
    assert_equal "Committee On Agenda", other.reload.name,
      "a committee referenced only by non-bc-coa records must remain untouched"
    assert_equal other.id, existing.reload.committee_id
  end

  test "migration refuses a conflicting manual chair and AI fallback without changing either" do
    good = Committee.create!(name: "Committee on Aging")
    bad = Committee.create!(name: "Committee On Agenda")
    member = Member.create!(name: "Synthetic Chair")
    fallback = CommitteeMembership.create!(committee: good, member: member, source: "ai_extracted", role: "member")
    manual = CommitteeMembership.create!(committee: bad, member: member, source: "admin_manual", role: "chair")
    meeting = Meeting.create!(body_name: "Committee On Agenda", committee: bad,
      starts_at: Time.zone.parse("2026-11-02 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda")
    before = [ manual, fallback, meeting, bad, good ].map(&:attributes)
    clear_enqueued_jobs
    error = nil
    assert_no_enqueued_jobs { error = assert_raises(RuntimeError) { run_correction } }
    assert_match "Conflicting active committee memberships", error.message
    assert_equal before, [ manual, fallback, meeting, bad, good ].map { |record| record.reload.attributes }
    assert_nil Redirect.find_by(source_path: "/committees/committee-on-agenda")
  end

  test "migration corrects only bc-coa meetings of a mixed-source committee when Aging does not exist" do
    bad = Committee.create!(name: "Committee On Agenda")
    unrelated = Meeting.create!(body_name: "Committee On Agenda", committee: bad,
      starts_at: Time.zone.parse("2026-11-04 10:00:00"),
      detail_page_url: "https://www.two-rivers.org/bc-other/page/not-aging")
    affected = Meeting.create!(body_name: "Committee On Agenda", committee: bad,
      starts_at: Time.zone.parse("2026-11-02 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda")
    before = [ bad, unrelated ].map(&:attributes)
    clear_enqueued_jobs

    2.times { assert_no_enqueued_jobs { run_correction } }

    assert_equal before, [ bad, unrelated ].map { |record| record.reload.attributes }
    good = Committee.find_by!(name: "Committee on Aging")
    assert_equal "Committee on Aging", affected.reload.body_name
    assert_equal good.id, affected.committee_id
    assert_equal "committee-on-aging", good.slug
    assert_equal 2, Committee.count
    assert_nil Redirect.find_by(source_path: "/committees/committee-on-agenda")
  end

  test "migration does not rename the only agenda committee when a non-corrected meeting still references it" do
    bad = Committee.create!(name: "Committee On Agenda")
    affected = Meeting.create!(body_name: "Committee On Agenda", committee: bad,
      starts_at: Time.zone.parse("2026-11-02 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda")
    leftover = Meeting.create!(body_name: "Senior Services Workshop", committee: bad,
      starts_at: Time.zone.parse("2026-11-16 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/senior-services-workshop")
    before = [ bad, leftover ].map(&:attributes)
    clear_enqueued_jobs

    2.times { assert_no_enqueued_jobs { run_correction } }

    assert_equal before, [ bad, leftover ].map { |record| record.reload.attributes }
    good = Committee.find_by!(name: "Committee on Aging")
    assert_not_equal bad.id, good.id
    assert_equal "Committee on Aging", affected.reload.body_name
    assert_equal good.id, affected.committee_id
    assert_equal "committee-on-agenda", bad.slug
    assert_equal "committee-on-aging", good.slug
    assert_nil Redirect.find_by(source_path: "/committees/committee-on-agenda")
    assert_equal 2, Committee.count
  end

  test "migration does not rename the only agenda committee when an outside appearance still references it" do
    bad = Committee.create!(name: "Committee On Agenda")
    affected = Meeting.create!(body_name: "Committee On Agenda", committee: bad,
      starts_at: Time.zone.parse("2026-11-02 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda")
    workshop = Meeting.create!(body_name: "Senior Services Workshop",
      starts_at: Time.zone.parse("2026-11-16 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/senior-services-workshop")
    topic = Topic.create!(name: "Senior center workshop", status: "approved")
    appearance = TopicAppearance.create!(topic: topic, meeting: workshop, committee: bad,
      appeared_at: workshop.starts_at, body_name: "Senior Services Workshop", evidence_type: "meeting_minutes")
    before = [ bad, workshop, appearance ].map(&:attributes)
    clear_enqueued_jobs

    assert_no_enqueued_jobs { run_correction }

    assert_equal before, [ bad, workshop, appearance ].map { |record| record.reload.attributes }
    good = Committee.find_by!(name: "Committee on Aging")
    assert_equal good.id, affected.reload.committee_id
    assert_equal "Committee on Aging", affected.body_name
    assert_equal bad.id, appearance.committee_id
    assert_nil Redirect.find_by(source_path: "/committees/committee-on-agenda")
  end

  private

  def run_correction
    migration = RenameCommitteeOnAgendaToCommitteeOnAging.new
    migration.verbose = false
    ActiveRecord::Base.transaction(requires_new: true) { migration.up }
  end
end
