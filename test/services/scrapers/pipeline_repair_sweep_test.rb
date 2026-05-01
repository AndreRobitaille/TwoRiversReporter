require "test_helper"

class Scrapers::PipelineRepairSweepTest < ActiveJob::TestCase
  test "page repair only enqueues parse meeting page" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/page-only", starts_at: 1.day.ago)

    result = nil

    assert_enqueued_with(job: Scrapers::ParseMeetingPageJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([]).call
    end

    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 1, document_downloads_enqueued: 0, agenda_parses_enqueued: 0, summaries_enqueued: 0, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end

  test "page repair does not enqueue for already parsed meeting" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/page-noop", starts_at: 1.day.ago)
    meeting.mark_processing!(:meeting_page_parsed_at)

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 0, result[:parse_meeting_pages_enqueued]
  end

  test "download repair enqueues when fetched_at is present but file is missing" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/download-only", starts_at: 1.day.ago)
    document = meeting.meeting_documents.create!(document_type: "packet_pdf", extracted_text: nil, fetched_at: Time.current)

    result = nil

    assert_enqueued_with(job: Documents::DownloadJob, args: [ document.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
    end

    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 1, agenda_parses_enqueued: 0, summaries_enqueued: 0, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end

  test "agenda repair only enqueues parse agenda when source exists and digest missing" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/agenda-only", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "agenda_html", extracted_text: nil)
    meeting.meeting_documents.first.file.attach(io: StringIO.new("agenda"), filename: "agenda.html", content_type: "text/html")

    result = nil

    assert_enqueued_with(job: Scrapers::ParseAgendaJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
    end

    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 1, agenda_parses_enqueued: 1, summaries_enqueued: 0, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end

  test "agenda repair does not rerun after agenda_checked_at is set" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/agenda-checked", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "agenda_html", extracted_text: nil)
    meeting.meeting_documents.first.file.attach(io: StringIO.new("agenda"), filename: "agenda.html", content_type: "text/html")
    meeting.mark_processing!(:agenda_checked_at)

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 0, result[:agenda_parses_enqueued]
  end

  test "repairs downloaded pdfs that have not been analyzed" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/pdf-needs-analysis", starts_at: 1.day.ago)
    document = meeting.meeting_documents.create!(document_type: "packet_pdf", extracted_text: nil, fetched_at: Time.current)
    document.file.attach(io: StringIO.new("%PDF-1.0 minimal"), filename: "packet.pdf", content_type: "application/pdf")

    assert_enqueued_with(job: Documents::AnalyzePdfJob, args: [ document.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
      assert_equal 1, result[:document_downloads_enqueued]
    end
  end

  test "summary repair only enqueues summarize meeting for minutes source" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/summary-only",
      starts_at: 1.day.ago,
      processing_state: {
        "topics_extracted_at" => true,
        "topics_extraction_status" => "empty",
        "votes_extracted_at" => true,
        "votes_extraction_status" => "empty",
        "committee_members_extracted_at" => true,
        "committee_members_extraction_status" => "empty"
      }
    )
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))

    result = nil

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
    end

    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 1, agenda_parses_enqueued: 0, summaries_enqueued: 1, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end

  test "summary waits for extraction completeness" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/summary-waits", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge("topics_extraction_status" => "parse_error"))

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ], since: Time.current).call

    assert_equal 0, result[:summaries_enqueued]
  end

  test "queues extraction repairs when markers are missing" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/extraction-repair", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "1. Call to order", fetched_at: Time.current)
    meeting.agenda_items.create!(title: "Budget Discussion", kind: "item", order_index: 1)

    assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
      assert_enqueued_with(job: ExtractVotesJob, args: [ meeting.id ]) do
        assert_enqueued_with(job: ExtractCommitteeMembersJob, args: [ meeting.id ]) do
          result = Scrapers::PipelineRepairSweep.new([ meeting.id ], since: Time.current).call
          assert_equal 1, result[:meetings_scoped]
          assert_equal 0, result[:summaries_enqueued]
        end
      end
    end
  end

  test "does not enqueue extraction repairs when markers are present" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/extraction-noop",
      starts_at: 1.day.ago,
      processing_state: {
        "topics_extracted_at" => true,
        "topics_extraction_status" => "empty",
        "votes_extracted_at" => true,
        "votes_extraction_status" => "empty",
        "committee_members_extracted_at" => true,
        "committee_members_extraction_status" => "empty"
      }
    )

    assert_no_enqueued_jobs only: [ ExtractTopicsJob, ExtractVotesJob, ExtractCommitteeMembersJob ] do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ], since: Time.current).call
      assert_equal 1, result[:meetings_scoped]
    end
  end

  test "retries extraction repairs when marker status is parse_error" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/extraction-retry",
      starts_at: 1.day.ago,
      processing_state: {
        "topics_extracted_at" => true,
        "topics_extraction_status" => "parse_error",
        "votes_extracted_at" => true,
        "votes_extraction_status" => "parse_error",
        "committee_members_extracted_at" => true,
        "committee_members_extraction_status" => "parse_error"
      }
    )
    meeting.agenda_items.create!(title: "Budget Discussion", kind: "item", order_index: 1)
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)

    assert_enqueued_with(job: ExtractTopicsJob, args: [ meeting.id ]) do
      assert_enqueued_with(job: ExtractVotesJob, args: [ meeting.id ]) do
        assert_enqueued_with(job: ExtractCommitteeMembersJob, args: [ meeting.id ]) do
          Scrapers::PipelineRepairSweep.new([ meeting.id ], since: Time.current).call
        end
      end
    end
  end

  test "better summary is still needed when only lower priority summary exists" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/better-summary",
      starts_at: 1.day.ago,
      processing_state: {
        "topics_extracted_at" => true,
        "topics_extraction_status" => "empty",
        "votes_extracted_at" => true,
        "votes_extraction_status" => "empty",
        "committee_members_extracted_at" => true,
        "committee_members_extraction_status" => "empty"
      }
    )
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))
    MeetingSummary.create!(meeting: meeting, summary_type: "agenda_preview", content: "done", generation_data: { "ok" => true })

    result = nil

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
    end

    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 1, agenda_parses_enqueued: 0, summaries_enqueued: 1, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end

  test "better minutes summary is needed even when transcript summary exists" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/minutes-upgrade", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))
    MeetingSummary.create!(meeting: meeting, summary_type: "transcript_recap", content: "done", generation_data: { "ok" => true })

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 1, result[:summaries_enqueued]
  end

  test "better transcript summary is needed even when packet summary exists" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/transcript-upgrade", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "transcript", extracted_text: "transcript text", fetched_at: Time.current)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge("topics_extraction_status" => "empty"))
    MeetingSummary.create!(meeting: meeting, summary_type: "packet_analysis", content: "done", generation_data: { "ok" => true })

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 1, result[:summaries_enqueued]
  end

  test "packet summary blocks packet-only repair" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/packet-noop",
      starts_at: 1.day.ago,
      processing_state: {}
    )
    meeting.meeting_documents.create!(document_type: "packet_pdf", extracted_text: "packet text", fetched_at: Time.current)
    MeetingSummary.create!(meeting: meeting, summary_type: "packet_analysis", content: "done", generation_data: { "ok" => true })

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 0, result[:summaries_enqueued]
  end

  test "existing full summary blocks another summary repair" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/full-summary",
      starts_at: 1.day.ago,
      processing_state: {
        "topics_extracted_at" => true,
        "topics_extraction_status" => "empty",
        "votes_extracted_at" => true,
        "votes_extraction_status" => "empty",
        "committee_members_extracted_at" => true,
        "committee_members_extraction_status" => "empty"
      }
    )
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))
    MeetingSummary.create!(meeting: meeting, summary_type: "minutes_recap", content: "done", generation_data: { "ok" => true })

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 0, result[:summaries_enqueued]
  end

  test "blank target summary still needs repair" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/blank-summary", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))
    meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: nil, generation_data: {})

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ], since: Time.current).call
      assert_equal 1, result[:summaries_enqueued]
    end
  end

  test "agenda-only extracted text does not enqueue summary job" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/agenda-no-summary", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "1. Call to order", fetched_at: Time.current)

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call

    assert_equal 0, result[:summaries_enqueued]
  end

  test "packet-only summary repair does not require votes or committee markers" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/packet-minimal", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "packet_pdf", extracted_text: "packet text", fetched_at: Time.current)

    MeetingSummary.create!(meeting: meeting, summary_type: "packet_analysis", content: nil, generation_data: {})

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
      assert_equal 1, result[:summaries_enqueued]
    end
  end

  test "transcript summary repair does not require votes or committee markers" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/transcript-minimal", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "transcript", extracted_text: "transcript text", fetched_at: Time.current)

    MeetingSummary.create!(meeting: meeting, summary_type: "transcript_recap", content: nil, generation_data: {})

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
      assert_equal 1, result[:summaries_enqueued]
    end
  end

  test "transcript-only summary repair enqueues without substantive agenda items" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/transcript-no-agenda", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "transcript", extracted_text: "transcript text", fetched_at: Time.current)
    MeetingSummary.create!(meeting: meeting, summary_type: "transcript_recap", content: nil, generation_data: {})

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
      assert_equal 1, result[:summaries_enqueued]
    end
  end

  test "minutes summary repair can enqueue without substantive agenda items" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/minutes-no-agenda", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))
    MeetingSummary.create!(meeting: meeting, summary_type: "minutes_recap", content: nil, generation_data: {})

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
      assert_equal 1, result[:summaries_enqueued]
    end
  end

  test "packet-like documents are recognized for summary targeting" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/board-packet", starts_at: 1.day.ago)
    meeting.meeting_documents.create!(document_type: "board_packet_pdf", extracted_text: "packet text", fetched_at: Time.current)
    MeetingSummary.create!(meeting: meeting, summary_type: "packet_analysis", content: nil, generation_data: {})

    assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
      assert_equal 1, result[:summaries_enqueued]
    end
  end

  test "enqueues repairs for parsed, downloaded, agenda, and summary gaps" do
    meeting = Meeting.create!(detail_page_url: "https://example.com/repair", starts_at: 1.day.ago)
    agenda_doc = meeting.meeting_documents.create!(document_type: "agenda_pdf", extracted_text: "1. Call to order")
    minutes_doc = meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text")
    meeting.mark_processing!(:topics_extracted_at)
    meeting.mark_processing!(:votes_extracted_at)
    meeting.mark_processing!(:committee_members_extracted_at)
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))

    result = nil

    assert_no_enqueued_jobs only: Scrapers::ParseMeetingPageJob do
      assert_enqueued_with(job: Documents::DownloadJob, args: [ agenda_doc.id ]) do
        assert_enqueued_with(job: Documents::DownloadJob, args: [ minutes_doc.id ]) do
          assert_enqueued_with(job: Scrapers::ParseAgendaJob, args: [ meeting.id ]) do
            assert_enqueued_with(job: SummarizeMeetingJob, args: [ meeting.id ]) do
              result = Scrapers::PipelineRepairSweep.new([ meeting.id ]).call
            end
          end
        end
      end
    end

    assert_equal 1, result[:meetings_scoped]
    assert_equal 0, result[:parse_meeting_pages_enqueued]
    assert_equal 2, result[:document_downloads_enqueued]
    assert_equal 1, result[:agenda_parses_enqueued]
    assert_equal 1, result[:summaries_enqueued]
  end

  test "does not enqueue repairs when meeting is already repaired" do
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/repaired",
      starts_at: 1.day.ago,
      processing_state: {
        "meeting_page_parsed_at" => true,
        "topics_extracted_at" => true,
        "topics_extraction_status" => "empty",
        "votes_extracted_at" => true,
        "votes_extraction_status" => "empty",
        "committee_members_extracted_at" => true,
        "committee_members_extraction_status" => "empty"
      },
      agenda_structure_digest: "digest"
    )
    document = meeting.meeting_documents.create!(document_type: "minutes_pdf", extracted_text: "minutes text", fetched_at: Time.current)
    document.file.attach(io: StringIO.new("minutes"), filename: "minutes.txt", content_type: "text/plain")
    document.update!(page_count: 1, text_chars: 7, avg_chars_per_page: 7.0, text_quality: "text")
    MeetingSummary.create!(meeting: meeting, summary_type: "minutes_recap", content: "done", generation_data: { "ok" => true })
    meeting.update!(processing_state: meeting.processing_state.merge(
      "topics_extraction_status" => "empty",
      "votes_extraction_status" => "empty",
      "committee_members_extraction_status" => "empty"
    ))

    result = Scrapers::PipelineRepairSweep.new([ meeting.id ], since: Time.current).call
    assert_equal({ meetings_scoped: 1, parse_meeting_pages_enqueued: 0, document_downloads_enqueued: 0, agenda_parses_enqueued: 0, summaries_enqueued: 0, topic_extractions_enqueued: 0, vote_extractions_enqueued: 0, committee_member_extractions_enqueued: 0 }, result)
  end

  test "scopes meetings from discovered ids and lookback window" do
    discovered = Meeting.create!(detail_page_url: "https://example.com/discovered", starts_at: 6.months.ago)
    Meeting.create!(detail_page_url: "https://example.com/recent", starts_at: 1.day.ago)

    recent = Meeting.find_by!(detail_page_url: "https://example.com/recent")

    assert_enqueued_with(job: Scrapers::ParseMeetingPageJob, args: [ recent.id ]) do
      result = Scrapers::PipelineRepairSweep.new([ discovered.id ]).call
      assert_equal 2, result[:meetings_scoped]
    end
  end
end
