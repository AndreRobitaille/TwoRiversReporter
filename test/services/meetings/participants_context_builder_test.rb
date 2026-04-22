require "test_helper"

module Meetings
  class ParticipantsContextBuilderTest < ActiveSupport::TestCase
    setup do
      @committee = Committee.create!(name: "City Council", committee_type: "city", status: "active")

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
        extracted_text: "1. CALL TO ORDER\nCouncilmembers: Mark Bittner, Doug Brandt, Katherine Dahlke, Shannon Derby"
      )

      result = ParticipantsContextBuilder.new(@meeting).build

      assert_equal [ "Mark Bittner", "Doug Brandt", "Katherine Dahlke", "Shannon Derby" ], result
    end

    test "falls back to canonical council roster when no agenda roll call exists" do
      result = ParticipantsContextBuilder.new(@meeting).build

      assert_equal [ "Mark Bittner", "Doug Brandt", "Kathy Dahlke", "Shannon Derby" ], result
    end

    test "returns blank result when no committee can be resolved" do
      meeting = Meeting.create!(
        body_name: "Harbor Commission Workshop",
        starts_at: Time.current,
        detail_page_url: "http://example.com/harbor"
      )

      result = ParticipantsContextBuilder.new(meeting).build

      assert_equal [], result
    end
  end
end
