require "test_helper"
require "ostruct"

module Documents
  class AnalyzePdfJobTest < ActiveJob::TestCase
    include ActiveJob::TestHelper

    def setup
      @meeting = Meeting.create!(
        body_name: "Public Works Committee",
        meeting_type: "Regular",
        starts_at: 1.week.ago,
        status: "held",
        detail_page_url: "http://example.com/m/analyze-pdf-test-#{SecureRandom.hex(4)}"
      )
    end

    test "triggers ExtractTopicsJob when processing minutes_pdf" do
      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = "Test minutes content for topic extraction"

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          assert_enqueued_with(job: ExtractTopicsJob, args: [ @meeting.id ]) do
            Documents::AnalyzePdfJob.perform_now(doc.id)
          end
        end
      end
    end

    test "does not trigger ExtractTopicsJob for packet_pdf" do
      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "packet_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "packet.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = "Packet content"

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      assert_no_enqueued_jobs(only: ExtractTopicsJob)
    end

    test "enqueues SummarizeMeetingJob with agenda_preview mode when document_type is agenda_pdf" do
      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "agenda_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "agenda.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("agenda item " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          assert_enqueued_with(job: SummarizeMeetingJob) do
            Documents::AnalyzePdfJob.perform_now(doc.id)
          end
        end
      end

      assert_enqueued_with(job: SummarizeMeetingJob, args: [ @meeting.id, { mode: :agenda_preview } ])
    end

    test "enqueues ParseAgendaJob when document_type is agenda_pdf" do
      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "agenda_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "agenda.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("agenda item " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          assert_enqueued_with(job: Scrapers::ParseAgendaJob, args: [ @meeting.id ]) do
            Documents::AnalyzePdfJob.perform_now(doc.id)
          end
        end
      end
    end

    test "runs agenda parsing before downstream minutes jobs when agenda already exists" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "5. NEW BUSINESS b. Storm Water Grant Resolution"
      )

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      assert_no_enqueued_jobs(only: Scrapers::ParseAgendaJob)

      minutes_jobs = enqueued_jobs.select do |job|
        [ ExtractVotesJob, ExtractCommitteeMembersJob, ExtractTopicsJob, SummarizeMeetingJob ].include?(job[:job])
      end
      assert_equal [ ExtractTopicsJob, ExtractVotesJob, ExtractCommitteeMembersJob, SummarizeMeetingJob ], minutes_jobs.map { |job| job[:job] }
    end

    test "runs agenda parsing before downstream minutes jobs when minutes_pdf has usable agenda_html" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_html",
        source_url: "http://example.com/agenda"
      ).tap do |agenda_doc|
        agenda_doc.file.attach(
          io: StringIO.new("<html><body>Agenda</body></html>"),
          filename: "agenda.html",
          content_type: "text/html"
        )
      end

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      assert_no_enqueued_jobs(only: Scrapers::ParseAgendaJob)

      minutes_jobs = enqueued_jobs.select do |job|
        [ ExtractVotesJob, ExtractCommitteeMembersJob, ExtractTopicsJob, SummarizeMeetingJob ].include?(job[:job])
      end
      assert_equal [ ExtractTopicsJob, ExtractVotesJob, ExtractCommitteeMembersJob, SummarizeMeetingJob ], minutes_jobs.map { |job| job[:job] }
    end

    test "does not enqueue downstream minutes jobs before agenda parsing when agenda parsing is available" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "5. NEW BUSINESS b. Storm Water Grant Resolution"
      )

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      jobs = enqueued_jobs.select { |job| [ ExtractVotesJob, ExtractCommitteeMembersJob, ExtractTopicsJob, Scrapers::ParseAgendaJob ].include?(job[:job]) }
      assert_equal [ ExtractTopicsJob, ExtractVotesJob, ExtractCommitteeMembersJob ], jobs.map { |job| job[:job] }, "minutes reruns should gate downstream work behind agenda parsing"
    end

    test "does not enqueue ParseAgendaJob when agenda_pdf extracted_text is whitespace-only" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "   \n\t  "
      )

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      assert_no_enqueued_jobs(only: Scrapers::ParseAgendaJob)
    end

    test "does not enqueue ParseAgendaJob when agenda_html has no attached file" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_html",
        source_url: "http://example.com/agenda"
      )

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      assert_no_enqueued_jobs(only: Scrapers::ParseAgendaJob)
    end

    test "does not enqueue agenda_preview summarize job for minutes_pdf" do
      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = "Minutes content"

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Documents::AnalyzePdfJob.perform_now(doc.id)
        end
      end

      agenda_preview_jobs = enqueued_jobs.select do |job|
        job[:job] == SummarizeMeetingJob && job[:args] == [ @meeting.id, { "mode" => "agenda_preview" } ]
      end

      assert_empty agenda_preview_jobs
    end

    test "does not mark minutes_pdf broken when agenda reconciliation fails closed but agenda_pdf fallback exists" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_html",
        source_url: "http://example.com/agenda"
      )
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "5. NEW BUSINESS b. Harbor Resolution"
      )

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Scrapers::ParseAgendaJob.stub :meeting_has_usable_agenda_source?, true do
            Scrapers::ParseAgendaJob.stub :parse_and_reconcile, ->(*) { raise Agendas::ReconcileItems::AmbiguousMatchError, "ambiguous" } do
              Documents::AnalyzePdfJob.perform_now(doc.id)
            end
          end
        end
      end

      assert_not_equal "broken", doc.reload.text_quality
    end

    test "does not mark minutes_pdf broken when agenda_html is missing and agenda_pdf fallback exists" do
      @meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "5. NEW BUSINESS b. Harbor Resolution"
      )

      doc = MeetingDocument.create!(
        meeting: @meeting,
        document_type: "minutes_pdf"
      )
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      pdfinfo_output = "Pages: 1\n"
      pdftotext_output = ("minutes text " * 30).strip

      Open3.stub :capture2e, [ pdfinfo_output, OpenStruct.new(success?: true) ] do
        Open3.stub :capture3, [ pdftotext_output, "", OpenStruct.new(success?: true) ] do
          Scrapers::ParseAgendaJob.stub :meeting_has_usable_agenda_source?, true do
            Scrapers::ParseAgendaJob.stub :parse_and_reconcile, ->(*) { raise Agendas::ReconcileItems::AmbiguousMatchError, "ambiguous" } do
              Documents::AnalyzePdfJob.perform_now(doc.id)
            end
          end
        end
      end

      assert_not_equal "broken", doc.reload.text_quality
    end
  end
end
