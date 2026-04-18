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
    assert_match(/\A\h{64}\z/, meeting.reload.agenda_structure_digest)
  end

  test "parses child agenda items from agenda_pdf extracted text when no agenda_html is attached" do
    meeting = Meeting.create!(
      body_name: "Advisory Recreation Board Meeting",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "agenda_posted",
      detail_page_url: "http://example.com/arb-pdf-parse-test"
    )

    meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      extracted_text: <<~TEXT.squish
        ADVISORY RECREATION BOARD MEETING AGENDA
        1. ROLL CALL
        5. NEW BUSINESS
        a. 2026 Great Neshotah Beach Campout - Action Recommended in support of City Council waiving ordinance(s) to allow the campout to take place
        b. 2026/27 DNR Non-Point Source & Storm Water Grant - Action recommended in support of City Council passing a resolution in support of applying for the grant
        c. 2026/27 DNR Stewardship Grant - Action recommended in support of City Council passing a resolution in support of applying for the grant
        6. OLD BUSINESS
      TEXT
    )

    assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
      Scrapers::ParseAgendaJob.perform_now(meeting.id)
    end

    section = meeting.agenda_items.find_by(title: "NEW BUSINESS")
    child = meeting.agenda_items.find_by(title: "2026/27 DNR Non-Point Source & Storm Water Grant")

    assert_equal "section", section.kind
    assert_equal "item", child.kind
    assert_equal section.id, child.parent_id
    assert_equal "b.", child.number
    assert_equal "in support of City Council passing a resolution in support of applying for the grant", child.recommended_action
  end

  test "falls back to agenda_pdf extracted text when agenda_html attachment is unavailable" do
    meeting = Meeting.create!(
      body_name: "Advisory Recreation Board Meeting",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "agenda_posted",
      detail_page_url: "http://example.com/arb-missing-html-test"
    )

    html_doc = meeting.meeting_documents.create!(document_type: "agenda_html", source_url: "http://example.com/agenda")
    html_doc.file.attach(
      io: StringIO.new("<html></html>"),
      filename: "agenda.html",
      content_type: "text/html"
    )
    meeting.meeting_documents.load
    agenda_doc = meeting.meeting_documents.detect { |document| document.document_type == "agenda_html" }
    assert_not_nil agenda_doc

    meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      extracted_text: "AGENDA 5. NEW BUSINESS b. 2026/27 DNR Non-Point Source & Storm Water Grant - Action recommended in support of City Council passing a resolution in support of applying for the grant 6. OLD BUSINESS"
    )

    Meeting.stub :find, ->(id) {
      assert_equal meeting.id, id
      meeting.meeting_documents.stub :find_by, ->(conditions) {
        case conditions[:document_type]
        when "agenda_html"
          agenda_doc
        when "agenda_pdf"
          meeting.meeting_documents.detect { |document| document.document_type == "agenda_pdf" }
        else
          nil
        end
      } do
        meeting
      end
    } do
      agenda_doc.file.stub :download, -> { raise ActiveStorage::FileNotFoundError, "missing attachment" } do
        Scrapers::ParseAgendaJob.parse_and_reconcile(meeting.id)
      end
    end

    assert_equal "2026/27 DNR Non-Point Source & Storm Water Grant", meeting.agenda_items.find_by(number: "b.")&.title
  end

  test "falls back to agenda_pdf extracted text when agenda_html parses no candidates" do
    meeting = Meeting.create!(
      body_name: "Advisory Recreation Board Meeting",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "agenda_posted",
      detail_page_url: "http://example.com/arb-empty-html-test"
    )

    html_doc = meeting.meeting_documents.create!(document_type: "agenda_html", source_url: "http://example.com/agenda")
    html_doc.file.attach(
      io: StringIO.new("<html><body><section class='agenda-section'></section></body></html>"),
      filename: "agenda.html",
      content_type: "text/html"
    )

    meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      extracted_text: "5. NEW BUSINESS b. 2026/27 DNR Non-Point Source & Storm Water Grant - Action recommended in support of City Council passing a resolution in support of applying for the grant 6. OLD BUSINESS"
    )

    assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
      Scrapers::ParseAgendaJob.perform_now(meeting.id)
    end

    assert_equal "2026/27 DNR Non-Point Source & Storm Water Grant", meeting.agenda_items.find_by(number: "b.")&.title
  end

  test "rerunning parse preserves agenda item ids when downstream references exist" do
    meeting = Meeting.create!(
      body_name: "Plan Commission Meeting",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "parsed",
      detail_page_url: "http://example.com/reconcile-test"
    )

    section = meeting.agenda_items.create!(number: "3.", title: "ACTION ITEMS", kind: "section", order_index: 1)
    item = meeting.agenda_items.create!(number: "A.", title: "Harbor Resolution", kind: "item", parent: section, order_index: 2)

    motion = meeting.motions.create!(agenda_item: item, description: "Approve resolution")

    meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      extracted_text: "3. ACTION ITEMS A. Harbor Resolution - Action Recommended Approve resolution"
    )

    original_id = item.id
    assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
      Scrapers::ParseAgendaJob.perform_now(meeting.id)
    end

    meeting.reload

    assert_equal original_id, meeting.agenda_items.find_by(number: "A.")&.id
    assert_equal 2, meeting.agenda_items.count
    assert_equal 2, meeting.agenda_items.pluck(:id).uniq.count
    assert_equal [
      [section.id, "3.", "ACTION ITEMS", "section", nil, 1],
      [original_id, "A.", "Harbor Resolution", "item", section.id, 2]
    ], meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
    assert_equal 1, meeting.agenda_items.where(number: "A.", title: "Harbor Resolution", kind: "item", parent_id: section.id).count
    assert_equal original_id, motion.reload.agenda_item_id
  end

  test "legacy flat meeting upgrades to structured rows on rerun when match is safe" do
    meeting = Meeting.create!(
      body_name: "Advisory Recreation Board Meeting",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "parsed",
      detail_page_url: "http://example.com/legacy-upgrade-safe"
    )

    legacy_item = meeting.agenda_items.create!(
      number: "b.",
      title: "2026/27 DNR Non-Point Source & Storm Water Grant",
      order_index: 1
    )
    motion = meeting.motions.create!(
      agenda_item: legacy_item,
      description: "Motion to support applying for the grant",
      outcome: "passed"
    )
    meeting.meeting_documents.create!(
      document_type: "agenda_pdf",
      extracted_text: "5. NEW BUSINESS b. 2026/27 DNR Non-Point Source & Storm Water Grant - Action recommended in support of City Council passing a resolution in support of applying for the grant"
    )

    Scrapers::ParseAgendaJob.perform_now(meeting.id)
    meeting.reload

    section = meeting.agenda_items.find_by(number: "5.")
    child = meeting.agenda_items.find_by(number: "b.")

    assert_equal legacy_item.id, child.id
    assert_equal "section", section.kind
    assert_equal "item", child.kind
    assert_equal section.id, child.parent_id
    assert_equal legacy_item.id, motion.reload.agenda_item_id
  end

  test "rerun is a no-op when parsed agenda structure digest is unchanged" do
    meeting = Meeting.create!(
      body_name: "Committee On Aging",
      meeting_type: "Regular",
      starts_at: Time.current,
      status: "parsed",
      detail_page_url: "http://example.com/digest-rerun",
      agenda_structure_digest: "existing-digest",
    )

    existing_section = meeting.agenda_items.create!(number: "1.", title: "CALL TO ORDER", kind: "section", order_index: 1)
    meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "1. CALL TO ORDER")

    original_meeting_state = meeting.attributes.slice("status", "agenda_structure_digest")
    original_items_snapshot = meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)

    Agendas::ReconcileItems.stub :digest_for_candidates, "existing-digest" do
      Agendas::ReconcileItems.stub :new, ->(*) { flunk "reconciler should not run when digest is unchanged" } do
        Scrapers::ParseAgendaJob.perform_now(meeting.id)
      end
    end

    meeting.reload

    assert_equal original_meeting_state, meeting.attributes.slice("status", "agenda_structure_digest")
    assert_equal existing_section.id, meeting.agenda_items.find_by(number: "1.")&.id
    assert_equal original_items_snapshot, meeting.agenda_items.order(:id).pluck(:id, :number, :title, :kind, :parent_id, :order_index)
  end

end
