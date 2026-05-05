class Scrapers::FullPipelineRefreshJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    discovered_meeting_ids = Scrapers::DiscoverMeetingsJob.run_inline!(enqueue_transcripts: true, enqueue_parse_jobs: false)
    parsed_meeting_ids = discovered_meeting_ids.select do |meeting_id|
      Scrapers::ParseMeetingPageJob.perform_now(meeting_id, enqueue_downloads: false)
      Meeting.find(meeting_id).meeting_page_parsed?
    end

    Scrapers::PipelineRepairSweep.new(discovered_meeting_ids, parsed_meeting_ids: parsed_meeting_ids).call
  end
end
