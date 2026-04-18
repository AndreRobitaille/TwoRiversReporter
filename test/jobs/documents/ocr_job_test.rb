require "test_helper"
require "ostruct"

module Documents
  class OcrJobTest < ActiveJob::TestCase
    test "enqueues minutes follow-up jobs after agenda parsing or no-op" do
      meeting = Meeting.create!(
        body_name: "Public Works Committee",
        meeting_type: "Regular",
        starts_at: 1.week.ago,
        status: "held",
        detail_page_url: "http://example.com/m/ocr-sequencing-test-#{SecureRandom.hex(4)}"
      )

      meeting.meeting_documents.create!(
        document_type: "agenda_pdf",
        extracted_text: "5. NEW BUSINESS b. Harbor Resolution"
      )

      doc = MeetingDocument.create!(meeting: meeting, document_type: "minutes_pdf")
      doc.file.attach(
        io: StringIO.new("%PDF-1.0 minimal"),
        filename: "minutes.pdf",
        content_type: "application/pdf"
      )

      Open3.stub :capture3, [ "OCR minutes text", "", OpenStruct.new(success?: true) ] do
        Documents::OcrJob.class_eval { define_method(:system) { |*| true } }
        begin
          Documents::OcrJob.perform_now(doc.id)
        ensure
          Documents::OcrJob.class_eval { remove_method(:system) }
        end
      end

      jobs = enqueued_jobs.select { |job| [ ExtractVotesJob, ExtractCommitteeMembersJob, ExtractTopicsJob, SummarizeMeetingJob ].include?(job[:job]) }

      assert_includes jobs.map { |job| job[:job] }, ExtractVotesJob
      assert_includes jobs.map { |job| job[:job] }, ExtractCommitteeMembersJob
      assert_includes jobs.map { |job| job[:job] }, SummarizeMeetingJob
      assert_includes jobs.map { |job| job[:job] }, ExtractTopicsJob
    end
  end
end
