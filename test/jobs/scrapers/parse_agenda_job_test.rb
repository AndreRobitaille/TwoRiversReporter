require "test_helper"

class Scrapers::ParseAgendaJobTest < ActiveJob::TestCase
  test "parses section headers as structural rows and child agenda items as substantive rows" do
    meeting = Meeting.create!(
      body_name: "Advisory Recreation Board Meeting",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "agenda_posted",
      detail_page_url: "http://example.com/arb-parse-test"
    )

    doc = meeting.meeting_documents.create!(document_type: "agenda_html", source_url: "http://example.com/agenda")
    doc.file.attach(
      io: StringIO.new(<<~HTML),
        <section class="agenda-section">
          <h2 class="section-header"><num>5.</num><span style="font-weight:bold">NEW BUSINESS</span></h2>
          <ol class="agenda-items">
            <li>
              <div class="Section1">
                <num>A.</num>
                <p><num>A.</num> Storm Water Grant</p>
                <p>Summary: Grant summary.</p>
                <p>Recommended Action: Approve grant resolution.</p>
                <a href="attachments/grant.pdf">Grant PDF</a>
              </div>
            </li>
          </ol>
        </section>
      HTML
      filename: "agenda.html",
      content_type: "text/html"
    )

    assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
      Scrapers::ParseAgendaJob.perform_now(meeting.id)
    end

    section = meeting.agenda_items.find_by(title: "NEW BUSINESS")
    child = meeting.agenda_items.find_by(title: "Storm Water Grant")

    assert_equal "section", section.kind
    assert_equal "item", child.kind
    assert_equal section.id, child.parent_id
    assert_equal "Grant summary.", child.summary
    assert_equal "Approve grant resolution.", child.recommended_action
    assert_equal 1, child.meeting_documents.count
    assert_equal "http://example.com/attachments/grant.pdf", child.meeting_documents.first.source_url
  end
end
