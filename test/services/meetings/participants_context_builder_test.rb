require "test_helper"

module Meetings
  class ParticipantsContextBuilderTest < ActiveSupport::TestCase
    setup do
      @committee = Committee.create!(name: "City Council", committee_type: "city", status: "active")
      CommitteeAlias.create!(committee: @committee, name: "City Council Reorganizational Meeting")

      @mark = Member.create!(name: "Mark Bittner")
      @doug = Member.create!(name: "Doug Brandt")
      @kathy = Member.create!(name: "Kathy Dahlke")
      @shannon = Member.create!(name: "Shannon Derby")

      [ @mark, @doug, @kathy, @shannon ].each do |member|
        CommitteeMembership.create!(committee: @committee, member: member, source: "seeded")
      end

      @meeting = Meeting.create!(
        body_name: "City Council Reorganizational Meeting",
        starts_at: Time.current,
        detail_page_url: "http://example.com/reorg"
      )
    end

    test "uses roster active at meeting date, not today's current roster" do
      committee = Committee.create!(name: "Historic City Council", committee_type: "city", status: "active")
      active_on_meeting_date = Member.create!(name: "Meeting Date Member")
      active_today_only = Member.create!(name: "Today Only Member")

      meeting_date = 2.weeks.ago.to_date
      CommitteeMembership.create!(
        committee: committee,
        member: active_on_meeting_date,
        source: "seeded",
        started_on: 1.month.ago.to_date,
        ended_on: 1.week.ago.to_date
      )
      CommitteeMembership.create!(
        committee: committee,
        member: active_today_only,
        source: "seeded",
        started_on: 1.day.ago.to_date
      )

      meeting = Meeting.create!(
        body_name: "Historic City Council",
        starts_at: meeting_date.to_time,
        detail_page_url: "http://example.com/historic"
      )

      result = Meetings::ParticipantsContextBuilder.new(meeting).build

      assert_includes result, "Meeting Date Member"
      assert_not_includes result, "Today Only Member"
    end

    test "uses agenda roll call names as meeting-specific overrides" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "1. CALL TO ORDER\nCouncilmembers: Mark Bittner, Doug Brandt\nAlso Present: Katherine Dahlke\nPresent: Shannon Derby"
      )

      agenda_text = "1. CALL TO ORDER\nCouncilmembers: Mark Bittner, Doug Brandt\nAlso Present: Katherine Dahlke\nPresent: Shannon Derby"
      result = Meetings::ParticipantsContextBuilder.new(@meeting, agenda_text).build

      assert_match(/Canonical roster: .*Doug Brandt.*Kathy Dahlke.*Mark Bittner.*Shannon Derby\./, result)
      assert_match(/Meeting roll call: .*Doug Brandt.*Shannon Derby\./, result)
      refute_match(/Katherine Dahlke/, result)
    end

    test "falls back to canonical council roster when no agenda roll call exists" do
      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_equal "Canonical roster: Doug Brandt, Kathy Dahlke, Mark Bittner, Shannon Derby. Meeting roll call: none.", result
    end

    test "uses meeting committee when body name does not resolve" do
      meeting = Meeting.create!(
        body_name: "Unmatched Body Name",
        committee: @committee,
        starts_at: Time.current,
        detail_page_url: "http://example.com/unmatched"
      )

      result = Meetings::ParticipantsContextBuilder.new(meeting).build

      assert_includes result, "Canonical roster: Doug Brandt, Kathy Dahlke, Mark Bittner, Shannon Derby."
    end

    test "excludes staff and non-voting members from canonical roster" do
      staff = Member.create!(name: "Staff Person")
      non_voting = Member.create!(name: "Non Voting Person")

      CommitteeMembership.create!(committee: @committee, member: staff, role: "staff", source: "seeded")
      CommitteeMembership.create!(committee: @committee, member: non_voting, role: "non_voting", source: "seeded")

      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_includes result, "Canonical roster: Doug Brandt, Kathy Dahlke, Mark Bittner, Shannon Derby."
      refute_includes result, "Staff Person"
      refute_includes result, "Non Voting Person"
    end

    test "does not scan other meeting documents when no agenda text is provided" do
      @meeting.meeting_documents.create!(
        document_type: "minutes_pdf",
        extracted_text: "Councilmembers: Mark Bittner, Doug Brandt"
      )

      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_equal "Canonical roster: Doug Brandt, Kathy Dahlke, Mark Bittner, Shannon Derby. Meeting roll call: none.", result
    end

    test "returns blank result when no committee can be resolved" do
      meeting = Meeting.create!(
        body_name: "Harbor Commission Workshop",
        starts_at: Time.current,
        detail_page_url: "http://example.com/harbor"
      )

      result = Meetings::ParticipantsContextBuilder.new(meeting).build

      assert_equal "", result
    end

    test "returns blank result when fallback committee lookup still fails" do
      CommitteeMembership.delete_all
      CommitteeAlias.delete_all
      Committee.delete_all

      meeting = Meeting.create!(
        body_name: "City Council Special Meeting",
        starts_at: Time.current,
        detail_page_url: "http://example.com/city-council"
      )

      result = Meetings::ParticipantsContextBuilder.new(meeting).build

      assert_equal "", result
    end
  end
end
