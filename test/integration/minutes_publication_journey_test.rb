require "test_helper"
require "minitest/mock"
require "open-uri"

class MinutesPublicationJourneyTest < ActionDispatch::IntegrationTest
  test "member page advances votes and attendance together after source revision" do
    user = User.create!(email_address: "synthetic-facts-reader@example.test", status: "active")
    sign_in_as(user)
    council = Committee.create!(name: "Synthetic Council", slug: "synthetic-council", committee_type: "city", status: "active")
    @member = Member.create!(name: "Alex Example")
    @meeting = Meeting.create!(committee: council, body_name: council.name, starts_at: 1.day.ago, detail_page_url: "https://example.test/member-facts")
    @document = @meeting.meeting_documents.create!(source_url: "https://example.test/member-facts.pdf", document_type: "minutes_pdf")
    revision("original", "Alex Example attended and voted no on park funding.")
    run_stage(:extract_votes, motions: [ { description: "Reserve synthetic park funding", outcome: "failed", votes: [ { member: @member.name, value: "no" } ] } ])
    run_stage(:extract_committee_members, voting_members_present: [ @member.name ], voting_members_absent: [], non_voting_staff: [], guests: [])
    assert_member_record("Reserve synthetic park funding", "No", "100%")
    previous_publication = @meeting.reload.minutes_publication_id

    revision("corrected", "Alex Example was absent. Blair Example voted yes to the revised library project.")
    run_stage(:extract_votes, motions: [ { description: "Approve revised synthetic library project", outcome: "passed", votes: [ { member: "Blair Example", value: "yes" } ] } ])
    assert_member_record("Reserve synthetic park funding", "No", "100%")
    assert_equal previous_publication, @meeting.reload.minutes_publication_id

    run_stage(:extract_committee_members, voting_members_present: [ "Blair Example" ], voting_members_absent: [ @member.name ], non_voting_staff: [], guests: [])
    assert_member_record("Approve revised synthetic library project", "Absent", "0%")
    assert_not_equal previous_publication, @meeting.reload.minutes_publication_id
    assert_equal "attendance_derived", @member.votes.last.evidence_basis
    assert_select "a[href=?]", meeting_path(@meeting), minimum: 1
    assert_not_includes response.body, "Reserve synthetic park funding"
    assert_equal 2, @meeting.minutes_publications.count
  end

  private

  def revision(bytes, text)
    URI.stub(:open, ->(*) { StringIO.new(bytes) }) { Documents::DownloadJob.perform_now(@document.id) }
    Documents::PublishText.new(@document.reload).call(raw_pages: [ text ], page_count: 1, quality: "text", extractor_version: "synthetic_v1")
  end

  def run_stage(method, data)
    service = Object.new
    service.define_singleton_method(method) { |*args, **kwargs| data.to_json }
    job = method == :extract_votes ? ExtractVotesJob : ExtractCommitteeMembersJob
    Ai::OpenAiService.stub(:new, service) { job.perform_now(@meeting.id) }
  end

  def assert_member_record(motion, vote, attendance)
    Ai::OpenAiService.stub :new, ->(*) { flunk "Reading a member page must not dispatch AI" } do
      get member_path(@member)
    end
    assert_response :success
    assert_select ".member-vote-row", count: 1
    assert_select ".member-vote-motion", text: /#{Regexp.escape(motion)}/
    assert_select ".vote-value", text: vote, count: 1
    assert_select ".member-attendance-stat", text: /\b#{Regexp.escape(attendance)}/, count: 1
  end
end
