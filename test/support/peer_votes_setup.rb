require_relative "council_attendance_setup"

module PeerVotesSetup
  include CouncilAttendanceSetup

  def setup_peer_votes
    setup_council_attendance
    @peer = Member.create!(name: "Taylor Comparison")
    @peer_period = @peer.council_service_periods.create!(period_key: "2024-appointment", started_on: "2024-05-01",
      start_source_version: @source, start_page: 1)
    @peer.member_positions.create!(kind: "city_council", title: "City Council Member", source: "official_website",
      source_url: "https://example.test/peer-roster", verified_at: Time.current)
    @comparison_meeting = council_meeting("2025-06-02", attendance: "present")
    @comparison_meeting.meeting_attendances.create!(member: @peer, status: "present", attendee_type: "voting_member")
    @agree = comparison_motion("Fund the distinctive bridge project")
    @split = comparison_motion("Reject the bridge alternative", peer: "no", outcome: "failed")
    @both_no = comparison_motion("Adopt an alternate bridge alignment", own: "no", peer: "no", outcome: "failed")
    @abstain = comparison_motion("Commission bridge analysis", own: "abstain")
    @recused = comparison_motion("Award a bridge design contract", own: "recused")
    @absent = comparison_motion("Acquire bridge easement", own: "absent", peer: "no")
    @unknown = comparison_motion("Approve bridge inspection", own: nil)
    @derived = comparison_motion("Fund bridge landscaping")
    @derived.votes.find_by!(member: @peer).update!(evidence_basis: "attendance_derived")
    comparison_motion("Approve minutes", own: "yes", peer: "yes")
    before_service = council_meeting("2024-04-16", attendance: "present")
    @outside = comparison_motion("Before peer appointment", meeting: before_service)
  end

  def comparison_motion(description, own: "yes", peer: "yes", meeting: @comparison_meeting, outcome: "passed", **attributes)
    motion = meeting.motions.create!(description: description, outcome: outcome, **attributes)
    motion.votes.create!(member: @member, value: own) if own
    motion.votes.create!(member: @peer, value: peer) if peer
    motion
  end
end
