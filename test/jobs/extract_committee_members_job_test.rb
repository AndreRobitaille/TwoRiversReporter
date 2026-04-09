require "test_helper"
require "minitest/mock"

class ExtractCommitteeMembersJobTest < ActiveSupport::TestCase
  setup do
    @committee = Committee.create!(name: "City Council")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: Time.zone.parse("2026-02-01 18:00"),
      committee: @committee,
      detail_page_url: "http://example.com/meeting-ecmj"
    )
    @doc = MeetingDocument.create!(
      meeting: @meeting,
      document_type: "minutes_pdf",
      extracted_text: "ROLL CALL\nPresent: Smith, Johnson\nAbsent: Davis\nAlso Present: City Manager, Kyle Kordell"
    )
  end

  def stub_ai_response(response_hash)
    mock_response = response_hash.to_json
    mock_service = Minitest::Mock.new
    mock_service.expect :extract_committee_members, mock_response do |text|
      text.is_a?(String)
    end
    mock_service
  end

  test "skips meeting without minutes text" do
    @doc.update!(extracted_text: nil)
    assert_no_difference "MeetingAttendance.count" do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
  end

  test "creates MeetingAttendance records for all attendees" do
    ai_response = {
      "voting_members_present" => [ "Smith", "Johnson" ],
      "voting_members_absent" => [ "Davis" ],
      "non_voting_staff" => [ { "name" => "Kyle Kordell", "capacity" => "City Manager" } ],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "MeetingAttendance.count", 4 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 2, @meeting.meeting_attendances.where(status: "present", attendee_type: "voting_member").count
    assert_equal 1, @meeting.meeting_attendances.where(status: "absent", attendee_type: "voting_member").count
    assert_equal 1, @meeting.meeting_attendances.where(attendee_type: "non_voting_staff").count

    staff = @meeting.meeting_attendances.find_by(attendee_type: "non_voting_staff")
    assert_equal "City Manager", staff.capacity
    mock_service.verify
  end

  test "creates Member records for new names" do
    ai_response = {
      "voting_members_present" => [ "New Person" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "Member.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert Member.find_by(name: "New Person")
    mock_service.verify
  end

  test "normalizes member names by stripping titles" do
    ai_response = {
      "voting_members_present" => [ "Councilmember Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    assert Member.find_by(name: "Smith")
    assert_nil Member.find_by(name: "Councilmember Smith")
    mock_service.verify
  end

  test "creates CommitteeMembership for new voting members" do
    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "CommitteeMembership.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    member = Member.find_by!(name: "Smith")
    membership = CommitteeMembership.find_by!(member: member, committee: @committee)
    assert_equal "member", membership.role
    assert_equal "ai_extracted", membership.source
    assert_equal @meeting.starts_at.to_date, membership.started_on
    assert_nil membership.ended_on
    mock_service.verify
  end

  test "creates CommitteeMembership with staff role for non-voting staff" do
    ai_response = {
      "voting_members_present" => [],
      "voting_members_absent" => [],
      "non_voting_staff" => [ { "name" => "Kyle Kordell", "capacity" => "City Manager" } ],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "CommitteeMembership.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    member = Member.find_by!(name: "Kyle Kordell")
    membership = CommitteeMembership.find_by!(member: member, committee: @committee)
    assert_equal "staff", membership.role
    assert_equal "ai_extracted", membership.source
    mock_service.verify
  end

  test "does not create membership for guests" do
    ai_response = {
      "voting_members_present" => [],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => [ { "name" => "Random Visitor" } ]
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_no_difference "CommitteeMembership.count" do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 1, @meeting.meeting_attendances.count
    mock_service.verify
  end

  test "does not overwrite admin_manual membership" do
    member = Member.create!(name: "Smith")
    existing = CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "chair", source: "admin_manual"
    )

    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_no_difference "CommitteeMembership.count" do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    existing.reload
    assert_equal "chair", existing.role
    assert_equal "admin_manual", existing.source
    mock_service.verify
  end

  test "does not duplicate existing ai_extracted membership" do
    member = Member.create!(name: "Smith")
    CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "ai_extracted"
    )

    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_no_difference "CommitteeMembership.count" do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end
    mock_service.verify
  end

  test "is idempotent — destroys and recreates attendance on re-run" do
    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }

    2.times do
      mock_service = stub_ai_response(ai_response)
      Ai::OpenAiService.stub :new, mock_service do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 1, @meeting.meeting_attendances.count
    assert_equal 1, CommitteeMembership.where(committee: @committee).count
  end

  test "skips membership reconciliation when meeting has no committee" do
    @meeting.update!(committee: nil)

    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "MeetingAttendance.count", 1 do
        assert_no_difference "CommitteeMembership.count" do
          ExtractCommitteeMembersJob.perform_now(@meeting.id)
        end
      end
    end
    mock_service.verify
  end

  test "departure detection ends membership after 2 consecutive absences from roll call" do
    member = Member.create!(name: "Departed Person")
    membership = CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "ai_extracted",
      started_on: Date.new(2025, 1, 1)
    )

    # Older meeting where member WAS present
    old_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2025-12-01 18:00"),
      detail_page_url: "http://example.com/old-meeting-ecmj"
    )
    MeetingDocument.create!(meeting: old_meeting, document_type: "minutes_pdf", extracted_text: "text")
    MeetingAttendance.create!(
      meeting: old_meeting, member: member,
      status: "present", attendee_type: "voting_member"
    )

    # Prior meeting where member was NOT present at all
    prior_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2026-01-15 18:00"),
      detail_page_url: "http://example.com/prior-meeting-ecmj"
    )
    MeetingDocument.create!(meeting: prior_meeting, document_type: "minutes_pdf", extracted_text: "text")
    # Note: No MeetingAttendance for Departed Person at prior_meeting -- they need at least
    # one attendance record at this meeting for it to count as a "meeting with attendance data"
    MeetingAttendance.create!(
      meeting: prior_meeting, member: Member.create!(name: "Someone Else"),
      status: "present", attendee_type: "voting_member"
    )

    # Now process current meeting (also missing this member)
    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    membership.reload
    assert_not_nil membership.ended_on
    assert_equal Date.new(2025, 12, 1), membership.ended_on
    mock_service.verify
  end

  test "departure detection does not end admin_manual membership" do
    member = Member.create!(name: "Admin Member")
    membership = CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "admin_manual"
    )

    prior_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2026-01-15 18:00"),
      detail_page_url: "http://example.com/prior-admin-ecmj"
    )
    MeetingDocument.create!(meeting: prior_meeting, document_type: "minutes_pdf", extracted_text: "text")
    MeetingAttendance.create!(
      meeting: prior_meeting, member: Member.create!(name: "Someone Else Prior"),
      status: "present", attendee_type: "voting_member"
    )

    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    membership.reload
    assert_nil membership.ended_on
    mock_service.verify
  end

  test "departure detection does not end membership for member listed as absent" do
    member = Member.create!(name: "Absent But Still Member")
    CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "ai_extracted",
      started_on: Date.new(2025, 1, 1)
    )

    prior_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2026-01-15 18:00"),
      detail_page_url: "http://example.com/prior-absent-ecmj"
    )
    MeetingDocument.create!(meeting: prior_meeting, document_type: "minutes_pdf", extracted_text: "text")
    MeetingAttendance.create!(
      meeting: prior_meeting, member: member,
      status: "absent", attendee_type: "voting_member"
    )

    ai_response = {
      "voting_members_present" => [ "Smith" ],
      "voting_members_absent" => [ "Absent But Still Member" ],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    membership = CommitteeMembership.find_by!(member: member, committee: @committee, ended_on: nil)
    assert_not_nil membership
    mock_service.verify
  end

  test "skips duplicate when two names resolve to same member" do
    member = Member.create!(name: "Smith")
    MemberAlias.create!(member: member, name: "Councilmember Smith")

    ai_response = {
      "voting_members_present" => [ "Smith", "Councilmember Smith" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "MeetingAttendance.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end
    mock_service.verify
  end

  test "skips duplicate when same member appears across categories" do
    member = Member.create!(name: "Kyle Kordell")

    ai_response = {
      "voting_members_present" => [ "Kyle Kordell" ],
      "voting_members_absent" => [],
      "non_voting_staff" => [ { "name" => "Kyle Kordell", "capacity" => "City Manager" } ],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "MeetingAttendance.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    attendance = @meeting.meeting_attendances.find_by(member: member)
    assert_equal "voting_member", attendance.attendee_type
    mock_service.verify
  end

  test "handles JSON parse error gracefully" do
    mock_service = Minitest::Mock.new
    mock_service.expect :extract_committee_members, "not valid json" do |text|
      true
    end

    Ai::OpenAiService.stub :new, mock_service do
      assert_nothing_raised do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 0, @meeting.meeting_attendances.count
    mock_service.verify
  end
end
