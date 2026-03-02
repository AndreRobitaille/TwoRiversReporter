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
  end
end
