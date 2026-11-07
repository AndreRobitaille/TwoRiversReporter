require "application_system_test_case"
require "minitest/mock"

class MemberMergeJourneysTest < ApplicationSystemTestCase
  test "admin merges matching votes and receives a recoverable refusal for conflicting records" do
    admin = User.create!(email_address: "synthetic-member-merge@example.test", status: "active", admin: true)
    # Eligibility fixture; sign-in uses the real browser email/cookie flow.
    admin.passkey_credentials.create!(external_id: "synthetic-merge-key", public_key: "fixture", sign_count: 0)
    sign_in_by_email(admin)

    target = Member.create!(name: "Alex Example")
    matching = Member.create!(name: "A. Example")
    conflicting = Member.create!(name: "Different Example")
    meeting = Meeting.create!(body_name: "Synthetic Council", starts_at: 1.day.ago, detail_page_url: "https://example.test/browser-member-merge")
    motion = meeting.motions.create!(description: "Synthetic garden approval", outcome: "passed")
    target_vote = motion.votes.create!(member: target, value: "yes", evidence_basis: "explicit")
    motion.votes.create!(member: matching, value: "yes", evidence_basis: "explicit")
    conflict_vote = motion.votes.create!(member: conflicting, value: "no", evidence_basis: "explicit")

    Ai::OpenAiService.stub :new, ->(*) { flunk "Member merge must not call AI" } do
      visit admin_member_path(matching)
      select target.name, from: "target_member_id"
      accept_confirm { click_button "Merge", exact: true }
      assert_current_path admin_member_path(target)
      assert_text "#{matching.name} merged into #{target.name}."
      refute Member.exists?(matching.id)
      assert_equal target.id, Member.resolve(matching.name).id
      assert_equal [ target_vote.id, conflict_vote.id ].sort, motion.votes.pluck(:id).sort

      visit admin_member_path(conflicting)
      assert_text "Synthetic garden approval"
      select target.name, from: "target_member_id"
      accept_confirm { click_button "Merge", exact: true }
      assert_current_path admin_member_path(conflicting)
      assert_text "Conflicting votes for motion #{motion.id}"
      assert_button "Merge", exact: true
      assert Member.exists?(conflicting.id)
      assert_equal "no", conflict_vote.reload.value
      assert_equal "yes", target_vote.reload.value
      refute MemberAlias.exists?(name: conflicting.name)

      visit admin_member_path(target)
      assert_text "Synthetic garden approval"
      assert_text matching.name
      assert_no_text conflicting.name, exact: true
      assert_equal [ target_vote.id ], target.votes.pluck(:id)
    end
  end
end
