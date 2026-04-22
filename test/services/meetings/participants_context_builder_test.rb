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
      old_member = Member.create!(name: "Old Roster Member")
      future_member = Member.create!(name: "Future Roster Member")
      CommitteeMembership.create!(committee: @committee, member: old_member, source: "seeded", started_on: 2.days.ago.to_date)
      CommitteeMembership.create!(committee: @committee, member: future_member, source: "seeded", started_on: 1.day.from_now.to_date)

      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_includes result, "Old Roster Member"
      assert_not_includes result, "Future Roster Member"
    end

    test "uses agenda roll call names as meeting-specific overrides" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "1. CALL TO ORDER\nCouncilmembers: Mark Bittner, Doug Brandt\nAlso Present: Katherine Dahlke\nPresent: Shannon Derby"
      )

      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_match(/Canonical roster: .*Doug Brandt.*Kathy Dahlke.*Mark Bittner.*Shannon Derby\./, result)
      assert_match(/Meeting roll call: .*Doug Brandt.*Shannon Derby\./, result)
      refute_match(/Katherine Dahlke/, result)
    end

    test "falls back to canonical council roster when no agenda roll call exists" do
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
  end
end
