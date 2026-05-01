class Scrapers::FullPipelineRefreshJob < ApplicationJob
  queue_as :default

  def perform(*_args)
    discovered_meeting_ids = Scrapers::DiscoverMeetingsJob.run_inline!(enqueue_transcripts: true)
    Scrapers::PipelineRepairSweep.new(discovered_meeting_ids).call
  end
end
