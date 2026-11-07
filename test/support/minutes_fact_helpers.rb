# Component tests supply the other stage through its real job/provider boundary.
# Cross-stage ordering and stale-source behavior live in fact_publication_test.
module MinutesFactHelpers
  def run_votes_job
    attendance = { "voting_members_present" => [], "voting_members_absent" => [], "non_voting_staff" => [], "guests" => [] }
    @meeting.meeting_attendances.includes(:member).each do |row|
      key = case row.attendee_type
      when "voting_member" then row.status == "present" ? "voting_members_present" : "voting_members_absent"
      when "non_voting_staff" then "non_voting_staff"
      else "guests"
      end
      attendance[key] << row.member.name
    end
    with_counterpart_provider(:extract_committee_members, attendance) { ExtractCommitteeMembersJob.perform_now(@meeting.id) }
    ExtractVotesJob.perform_now(@meeting.id)
  end

  def run_attendance_job
    with_counterpart_provider(:extract_votes, { "motions" => [] }) { ExtractVotesJob.perform_now(@meeting.id) }
    ExtractCommitteeMembersJob.perform_now(@meeting.id)
  end

  private

  def with_counterpart_provider(method, data)
    service = Object.new
    service.define_singleton_method(method) { |*args, **kwargs| data.to_json }
    original = Ai::OpenAiService.method(:new)
    Ai::OpenAiService.define_singleton_method(:new) { |*args| service }
    yield
  ensure
    Ai::OpenAiService.define_singleton_method(:new, original)
  end
end
