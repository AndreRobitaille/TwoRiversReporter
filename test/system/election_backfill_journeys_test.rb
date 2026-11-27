require "application_system_test_case"
require "tempfile"
require "minitest/mock"

class ElectionBackfillJourneysTest < ApplicationSystemTestCase
  test "a past election accepts a manually labeled SRT with repeated words and resumes the editor's work" do
    admin = User.create!(email_address: "backfill-editor@example.test", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "backfill-editor-key", public_key: "public-key", sign_count: 0)
    sign_in_by_email(admin)
    visit admin_root_path
    find(".adm-launcher").click_link "Elections"
    select "2025", from: "Change election"
    assert_current_path admin_elections_path(year: 2025)
    assert_selector "h1", text: /Spring 2025 Council election/
    assert_text "Bill LeClair, Tim Petri, and Scott Stechmesser"
    click_link "Label another forum"
    captions = "1\r\n00:00:01,000 --> 00:00:02,500\r\nYes\r\n\r\n2\r\n00:00:05,125 --> 00:00:08,000\r\nYes again.\r\n"
    Tempfile.create([ "forum", ".srt" ]) do |file|
      file.binmode
      file.write(captions)
      file.flush
      attach_file "Open SRT or VTT captions", file.path
      assert_selector "#transcript .word", count: 3
      find("#transcript .word", text: "Yes", match: :first).click
      find("#speakers button[aria-label='Moderator']:enabled").click
      find("#speakers button[aria-label='Tim Petri']:enabled").click
      assert_text "Assigned to Tim Petri"
      click_button "Review & save"
      fill_in "Recording title", with: "Backfill forum"
      fill_in "Recording URL", with: "https://example.test/forum/backfill"
      click_button "Keep labeling"
      page.refresh
      attach_file "Open SRT or VTT captions", file.path
      assert_selector "#transcript .word.labeled[title='Tim Petri']", count: 1
      assert_selector "#reading-title", text: "Backfill forum"
      click_button "Next unlabeled passage"
      find("#speakers button[aria-label='Bill LeClair']:enabled").click
      click_button "Review & save"
      fill_in "Organizer", with: "Example League"
      fill_in "Forum date", with: "03/06/2025"
      assert_equal "2025-04-01", find_field("Election date").value
      check "Speaker labels were verified against the recording."
      click_button "Save forum"
      assert_selector "h1", text: /Backfill forum/i
      page.refresh
      source = CampaignSource.find_by!(source_url: "https://example.test/forum/backfill")
      segments = source.current_version.prepared_transcript.fetch("segments")
      assert_equal [ [ "Tim Petri", "Yes", 1000, 2500 ], [ "Bill LeClair", "Yes again.", 5125, 8000 ] ],
        segments.map { |s| s.values_at("speaker", "text", "start_ms", "end_ms") }
      assert_text "Complete prepared transcript"
      assert_equal Date.new(2025, 4, 1), source.election_on
      assert_equal 0, CampaignRequest.count
      click_link "Edit speaker labels"
      assert_selector "#transcript .word.labeled[title='Tim Petri']", count: 1
      find("#transcript .word", text: "Yes", match: :first).click
      find("#speakers button[aria-label='Moderator']:enabled").click
      click_button "Review & save"
      find("summary", text: "Recording details").click
      fill_in "Recording URL", with: "https://example.test/another-recording"
      check "Speaker labels were verified against the recording."
      click_button "Save forum"
      assert_selector "#review-error", text: /same recording/
      assert_equal 1, source.versions.reload.count
      fill_in "Recording URL", with: source.source_url
      click_button "Save forum"
      assert_selector "h1", text: /Backfill forum/i
      assert_equal 2, source.versions.reload.count
      assert_equal "Moderator", source.reload.current_version.prepared_transcript.fetch("segments").first.fetch("speaker")
      Dir.mktmpdir do |folder|
        click_link "Edit speaker labels"
        assert_selector ".word.labeled[title='Moderator']", count: 1
        driver = page.driver.browser
        driver.execute_cdp("Browser.setDownloadBehavior", behavior: "allow", downloadPath: folder)
        click_button "Download backup"
        click_button "Export labeled text"
        wait = Selenium::WebDriver::Wait.new(timeout: 5)
        backup = wait.until { Dir[File.join(folder, "*-speakers.json")].first }
        export = wait.until { Dir[File.join(folder, "*-labeled.txt")].first }
        assert_includes File.read(export), "[00:00:05–00:00:08] Bill LeClair\nYes again."
        assert_equal captions, JSON.parse(File.read(backup)).fetch("captions")
        visit desk_admin_campaign_forum_path(year: "2026")
        attach_file "Resume a saved speaker project", backup
        assert_selector "#transcript .word.labeled[title='Bill LeClair']", count: 2
        click_button "Review & save"
        find("summary", text: "Recording details").click
        assert_field "Recording URL", with: source.source_url
        assert_field "Organizer", with: "Example League"
        assert_field "Election date", with: "2025-04-01"
        assert_unchecked_field "Speaker labels were verified against the recording."
      end
    end
  end

  test "an editor can find the HTR article on a phone and save just the Council answers under its year" do
    admin = User.create!(email_address: "questionnaire-editor@example.test", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "questionnaire-editor-key", public_key: "key", sign_count: 0)
    sign_in_by_email(admin)
    page.current_window.resize_to(390, 844)
    visit admin_elections_path
    year_select = find_field("Change election")
    current_year = year_select.value
    assert_no_button "Open", exact: true
    assert_operator year_select.evaluate_script("this.getBoundingClientRect().bottom"), :<=, page.evaluate_script("innerHeight")
    select "2025", from: "Change election"
    assert_current_path admin_elections_path(year: 2025)
    assert_selector "h1", text: /Spring 2025 Council election/
    assert_no_selector "#election-needs-you"
    page.refresh
    assert_field "Change election", with: "2025"
    page.go_back
    assert_current_path admin_elections_path
    assert_field "Change election", with: current_year
    select "2025", from: "Change election"
    assert_current_path admin_elections_path(year: 2025)
    within "section[aria-labelledby='election-backfill-tasks']" do
      click_link "Add Council answers"
    end
    assert_selector "h1", text: "2025 candidate questionnaire"
    assert_link "Open HTR article", href: Campaigns::ElectionBackfill.lead(2025, "htr", kind: "article").fetch("url")
    school = "Two Rivers Board of Education\nSchool candidate: Other response"
    fill_in "Paste the Council answers", with: school
    click_button "Save Council answers"
    assert_selector "[role=alert]", text: /must include Council answers/
    assert_field "Paste the Council answers", with: school
    council = "Question one?\nFirst candidate: I worked with the Two Rivers Board of Education.\nFinal candidate: This is my last answer."
    fill_in "Paste the Council answers", with: "#{council}\n#{school}"
    click_button "Save Council answers"
    assert_selector "[role=status]", text: /Council answers saved for 2025.*school board section was left out/
    source = CampaignSource.sole
    assert_equal [ Date.new(2025, 4, 1), "selected_excerpts", council ], [ source.election_on, source.coverage, source.current_version.body ]
    assert_selector "#questionnaire-progress", text: "Analysis pending"
    click_link "2025 election"
    assert_no_link "Add Council answers"
    within "section[aria-labelledby='election-done']" do
      assert_text "Answers saved"
      click_link "Read answers"
    end
    assert_selector "[data-campaign-source-text]", text: "Final candidate: This is my last answer."
    assert_no_text "School candidate"
    click_link "Edit answers"
    assert_field "Paste the Council answers", with: council
    fill_in "Paste the Council answers", with: "#{council} Corrected."
    click_button "Save Council answers"
    assert_selector "[role=status]", text: "Council answers saved for 2025."
    page.refresh
    assert_text "last answer. Corrected."
    assert_equal 2, source.versions.count
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
  end

  test "switching between split recordings keeps each labeled passage and its reading position" do
    admin = User.create!(email_address: "desk-switch@example.test", admin: true, status: "active")
    admin.passkey_credentials.create!(external_id: "desk-switch", public_key: "key", sign_count: 0)
    sign_in_by_email(admin)
    edition = Campaigns::ElectionBackfill.for(2025)
    Dir.mktmpdir do |dir|
      paths = %w[business business_continued].index_with do |key|
        path = Pathname(dir).join("#{key}.vtt")
        path.write("WEBVTT\n\n00:00:01.000 --> 00:02:00.000\n#{key} " + ("may we begin now " * 350))
        path
      end
      captions = paths.transform_keys { |key| edition.fetch("sources").fetch(key).fetch("url") }
      Campaigns::ElectionBackfill.stub(:caption_path, ->(lead) { captions[lead&.fetch("url", nil)] }) do
        visit desk_admin_campaign_forum_path(year: 2025, lead: "business")
        assert_selector "#transcript .word", minimum: 1000, visible: :all
        words = all("#transcript .word", minimum: 4)
        page.driver.browser.action.move_to(words[0].native).click_and_hold.move_to(words[3].native).release.perform
        find("#transcript").send_keys("3")
        assert_selector ".word.labeled[title='Tim Petri']", count: 4
        find("#speakers button[aria-label='Moderator']:enabled").click
        assert_selector ".word.labeled[title='Moderator']", count: 4
        click_button "Undo"
        assert_selector ".word.labeled[title='Tim Petri']", count: 4
        click_button "Redo"
        find("summary", text: /Labeled passages/).click
        find("#label-list button", text: /Moderator/).click
        assert_text "Assigned to Moderator"
        pos = page.evaluate_script("document.querySelector('#transcript').scrollTop = 500")
        select "Business Association · Short restart", from: "recording-switch"
        assert_selector "#reading-title", text: /Continued/
        assert_selector "#transcript .word", text: "business_continued"
        assert_no_selector ".word.labeled"
        click_link "Elections · 2025", exact: false
        within find("li", text: /Opening recording/) do
          assert_text "4 words labeled in this browser"
          click_link "Resume labeling"
        end
        assert_selector ".word.labeled[title='Moderator']", count: 4, visible: :all
        assert_in_delta pos, page.evaluate_script("document.querySelector('#transcript').scrollTop"), 5
        assert_selector "#watch[href*='5Wmgl7ZFUgg']"
        page.current_window.resize_to(390, 844)
        find("summary", text: /Labeled passages/).click
        find("#label-list button", text: /Moderator/).click
        select "Bill LeClair", from: "quick-speaker"
        assert_selector ".word.labeled[title='Bill LeClair']", count: 4
        assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, 390
      end
    end
  end
end
