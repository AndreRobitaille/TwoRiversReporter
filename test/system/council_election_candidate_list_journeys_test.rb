require "application_system_test_case"

class CouncilElectionCandidateListJourneysTest < ApplicationSystemTestCase
  test "an editor can open a discovered filing story and publish its names" do
    travel_to Time.zone.local(2027, 1, 7, 18) do
      admin = User.create!(email_address: "filing-story@example.test", admin: true, status: "active")
      admin.passkey_credentials.create!(external_id: "filing-story-key", public_key: "public-key", sign_count: 0)
      council = Committee.create!(name: "City Council")
      url = "https://www.seehafernews.com/2027/01/07/two-rivers-council-ballot/"
      ElectionFilingWatch.create!(election_on: Date.new(2027, 4, 6), article_url: url)
      sign_in_by_email(admin)
      visit admin_elections_path(year: 2027)
      within "#candidate-list-task" do
        assert_link "Read the filing story", href: url
        click_link "Add candidates"
      end
      assert_field "Article link (optional)", with: url
      fill_in "Candidate names", with: "Avery Bell\nRobin Green"
      click_button "Publish candidates"
      assert_selector "#candidate-list", text: "Avery Bell and Robin Green"
      using_session(:resident) do
        visit committee_path(council.slug)
        within "#spring-election" do
          assert_link "Avery Bell"
          assert_link "Robin Green"
          assert_link "Candidate list source", href: url
        end
      end
    end
  end

  test "an editor publishes, corrects and removes names and the guide reflects the saved list" do
    travel_to Time.zone.local(2026, 11, 27) do
      admin = User.create!(email_address: "candidate-browser@example.test", admin: true, status: "active")
      admin.passkey_credentials.create!(external_id: "candidate-browser-key", public_key: "public-key", sign_count: 0)
      council = Committee.create!(name: "City Council")
      member = Member.create!(name: "Mark Bittner")
      CommitteeMembership.create!(committee: council, member: member, role: "member", source: "admin_manual")

      page.current_window.resize_to(390, 844)
      sign_in_by_email(admin)
      visit admin_root_path
      find(".adm-launcher").click_link "Elections"
      within "section[aria-labelledby=election-needs-you] #candidate-list-task" do
        assert_selector "h3", text: "2027 Candidates"
        click_link "Add candidates"
      end
      assert_selector "h1", text: "2027 Candidates"
      assert_text "Type or paste one name per line."
      fill_in "Candidate names", with: "Mark Bittner\nExample Challenger\nAnother Candidate"
      assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      click_button "Publish candidates"
      assert_selector "section[aria-labelledby=election-done] #candidate-list", text: /Mark Bittner, Example Challenger, and Another Candidate/
      assert_no_selector "#candidate-list-task"

      using_session(:resident) do
        page.current_window.resize_to(390, 844)
        visit committee_path(council.slug)
        assert_link member.name, href: member_path(member)
        assert_selector "#spring-election details:not([open])"
        find("#spring-election summary").click
        within "#spring-election" do
          assert_selector "h3", text: "2027 Candidates"
          assert_link member.name, href: member_path(member)
          click_link "Example Challenger"
        end
        assert_selector "h1", text: /Example Challenger/i
        assert_text "2027 City Council candidate"
        assert_text "We haven’t recorded campaign answers"
        assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390

        page.current_window.resize_to(1280, 900)
        visit committee_path(council.slug)
        assert_selector "#spring-election details[open]"
        assert_selector "#spring-election .election-person-row", text: member.name, count: 1
        assert_selector "#spring-election .election-person-row", text: "Example Challenger"
      end

      page.current_window.resize_to(1280, 900)
      click_link "Edit candidates"
      assert_selector "h1", text: "2027 Candidates"
      assert_field "Candidate names", with: "Mark Bittner\nExample Challenger\nAnother Candidate"
      fill_in "Candidate names", with: "Mark Bittner\nCorrected Challenger"
      click_button "Save changes"
      assert_selector "#candidate-list", text: /Mark Bittner and Corrected Challenger/

      using_session(:resident) do
        visit committee_path(council.slug)
        assert_selector "#seat-corrected-challenger"
        assert_no_selector "#seat-example-challenger, #seat-another-candidate"
      end

      click_link "Edit candidates"
      dismiss_confirm("Remove all 2027 candidates from the guide?") { click_button "Remove candidate list" }
      assert_field "Candidate names", with: "Mark Bittner\nCorrected Challenger"
      accept_confirm("Remove all 2027 candidates from the guide?") { click_button "Remove candidate list" }
      assert_link "Add candidates", href: new_admin_election_candidate_list_path(year: 2027)
      assert_selector "section[aria-labelledby=election-needs-you] #candidate-list-task"
      using_session(:resident) do
        visit committee_path(council.slug)
        assert_selector "#spring-election h3", text: "Council terms ending in 2027"
        assert_no_selector "#spring-election h3", text: "2027 Candidates", exact_text: true
        assert_no_selector "#seat-corrected-challenger"
      end
    end
  end
end
