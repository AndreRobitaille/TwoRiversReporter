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

    test "uses agenda roll call names as meeting-specific overrides" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "1. CALL TO ORDER\nCouncilmembers: Mark Bittner, Doug Brandt\nPresent: Katherine Dahlke, Shannon Derby"
      )

      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_match(/Meeting participants:/, result)
      assert_match(/Mark Bittner/, result)
      assert_match(/Doug Brandt/, result)
      assert_match(/Kathy Dahlke|Katherine Dahlke/, result)
      assert_match(/Shannon Derby/, result)
    end

    test "falls back to canonical council roster when no agenda roll call exists" do
      result = Meetings::ParticipantsContextBuilder.new(@meeting).build

      assert_equal "Meeting participants: Doug Brandt, Kathy Dahlke, Mark Bittner, Shannon Derby.", result
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
