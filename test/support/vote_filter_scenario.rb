require_relative "council_attendance_setup"

module VoteFilterScenario
  include CouncilAttendanceSetup

  def setup_vote_filters
    setup_council_attendance
    SiteSetting.instance.update!(access_mode: "open")
    @peer = Member.create!(name: "Taylor Search")
    @topic = Topic.create!(name: "riverfront redevelopment", status: "approved", resident_impact_score: 4)
    @second_topic = Topic.create!(name: "downtown improvements", status: "approved")
    @blocked = Topic.create!(name: "UNPUBLISHED_TOPIC_CANARY", status: "blocked")
    @meeting = council_meeting("2025-06-02", attendance: "present")
    @special = council_meeting("2025-06-09", title: "Special City Council Meeting", attendance: "present")
    @grant_votes = 26.times.map do |index|
      filter_vote("Riverfront grant agreement #{index}", meeting: index == 25 ? @special : @meeting,
        peer: index.zero? ? "no" : "yes")
    end
    @abstention = filter_vote("Riverfront grant study", peer: "abstain")
    @routine = filter_vote("Approve consent agenda")
    @procedural_dissent = filter_vote("Enter closed session for negotiations", peer: "no")
    @other_body = Meeting.create!(body_name: "Planning Commission", starts_at: Time.zone.parse("2025-07-01 18:00"),
      detail_page_url: "https://example.test/planning-filter")
    @planning_vote = filter_vote("Riverfront grant planning", meeting: @other_body)
  end

  def filter_vote(description, meeting: @meeting, peer: "yes")
    item = meeting.agenda_items.create!(title: "Hamilton redevelopment", number: "6")
    item.topics << [ @topic, @second_topic, @blocked ]
    motion = meeting.motions.create!(agenda_item: item, description: description, outcome: "passed")
    vote = motion.votes.create!(member: @member, value: "yes")
    motion.votes.create!(member: @peer, value: peer)
    vote
  end
end
