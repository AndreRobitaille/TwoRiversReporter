require "test_helper"

module Meetings
  class WindowDuplicateCleanupTest < ActiveSupport::TestCase
    test "deletes empty future duplicate and keeps meeting with documents" do
      starts_at = 5.days.from_now.change(usec: 0)
      keeper = Meeting.create!(
        body_name: "Public Works Committee",
        starts_at: starts_at,
        detail_page_url: "https://example.com/public-works-with-agenda"
      )
      keeper.meeting_documents.create!(document_type: "agenda_pdf", source_url: "https://example.com/agenda.pdf")
      duplicate = Meeting.create!(
        body_name: "Public Works Committee Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/public-works-empty"
      )

      assert_difference -> { Meeting.count }, -1 do
        report = WindowDuplicateCleanup.call(dry_run: false)
        assert_equal [ duplicate.id ], report[:deleted_ids]
        assert_equal [ keeper.id ], report[:kept_ids]
      end

      assert Meeting.exists?(keeper.id)
      refute Meeting.exists?(duplicate.id)
    end

    test "dry run reports empty future duplicate without deleting it" do
      starts_at = 6.days.from_now.change(usec: 0)
      keeper = Meeting.create!(
        body_name: "Plan Commission Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/plan-with-packet"
      )
      keeper.meeting_documents.create!(document_type: "packet_pdf", source_url: "https://example.com/packet.pdf")
      duplicate = Meeting.create!(
        body_name: "Plan Commission Meeting - Cancelled",
        starts_at: starts_at,
        detail_page_url: "https://example.com/plan-empty"
      )

      assert_no_difference -> { Meeting.count } do
        report = WindowDuplicateCleanup.call(dry_run: true)
        assert_equal [ duplicate.id ], report[:deleted_ids]
        assert_equal [ keeper.id ], report[:kept_ids]
      end

      assert Meeting.exists?(keeper.id)
      assert Meeting.exists?(duplicate.id)
    end

    test "deletes empty past duplicate in meetings window and keeps record with useful data" do
      starts_at = 2.days.ago.change(usec: 0)
      keeper = Meeting.create!(
        body_name: "Public Utilities Committee Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/past-with-minutes"
      )
      keeper.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.com/minutes.pdf")
      duplicate = Meeting.create!(
        body_name: "Public Utilities Committee Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/past-empty"
      )

      assert_difference -> { Meeting.count }, -1 do
        report = WindowDuplicateCleanup.call(dry_run: false)
        assert_equal [ duplicate.id ], report[:deleted_ids]
        assert_equal [ keeper.id ], report[:kept_ids]
      end

      assert Meeting.exists?(keeper.id)
      refute Meeting.exists?(duplicate.id)
    end

    test "ignores duplicates outside meetings window" do
      starts_at = 30.days.ago.change(usec: 0)
      keeper = Meeting.create!(
        body_name: "Public Utilities Committee Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/old-past-with-minutes"
      )
      keeper.meeting_documents.create!(document_type: "minutes_pdf", source_url: "https://example.com/old-minutes.pdf")
      Meeting.create!(
        body_name: "Public Utilities Committee Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/old-past-empty"
      )

      assert_no_difference -> { Meeting.count } do
        report = WindowDuplicateCleanup.call(dry_run: false)
        assert_empty report[:deleted_ids]
        assert_empty report[:kept_ids]
      end
    end

    test "keeps cancelled meeting when all future duplicates are empty" do
      starts_at = 8.days.from_now.change(usec: 0)
      duplicate = Meeting.create!(
        body_name: "City Council Work Session",
        starts_at: starts_at,
        detail_page_url: "https://example.com/work-session"
      )
      keeper = Meeting.create!(
        body_name: "City Council Work Session – CANCELED",
        starts_at: starts_at,
        detail_page_url: "https://example.com/work-session-canceled"
      )

      assert_difference -> { Meeting.count }, -1 do
        report = WindowDuplicateCleanup.call(dry_run: false)
        assert_equal [ duplicate.id ], report[:deleted_ids]
        assert_equal [ keeper.id ], report[:kept_ids]
      end

      assert Meeting.exists?(keeper.id)
      refute Meeting.exists?(duplicate.id)
    end

    test "skips future duplicate when documentless record has useful data" do
      starts_at = 7.days.from_now.change(usec: 0)
      keeper = Meeting.create!(
        body_name: "City Council Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/council-with-agenda"
      )
      keeper.meeting_documents.create!(document_type: "agenda_pdf", source_url: "https://example.com/council-agenda.pdf")
      duplicate = Meeting.create!(
        body_name: "City Council Meeting",
        starts_at: starts_at,
        detail_page_url: "https://example.com/council-with-summary"
      )
      duplicate.meeting_summaries.create!(summary_type: "agenda_preview", generation_data: { "headline" => "Preview" })

      assert_no_difference -> { Meeting.count } do
        report = WindowDuplicateCleanup.call(dry_run: false)
        assert_empty report[:deleted_ids]
        assert_equal [ [ keeper.id, duplicate.id ] ], report[:skipped_groups]
      end
    end
  end
end
