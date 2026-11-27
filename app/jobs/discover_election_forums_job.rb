class DiscoverElectionForumsJob < ApplicationJob
  queue_as :default
  retry_on Documents::TranscriptDownloader::DownloadError, wait: 30.minutes, attempts: 2

  def perform(year = nil)
    date = Campaigns::ElectionBackfill.election_on(year || Date.current.year)
    return unless date
    return if year.nil? && !Date.current.between?(Date.new(date.year, 2, 1), date)

    through = [ Date.current, date ].min
    Campaigns::ForumDiscovery.collect_notices(date, through: through)
    forums = ElectionForum.where(election_on: date, held_on: ..through).order(:held_on).to_a
    Campaigns::ForumDiscovery.collect_recordings(forums)
    forums.each do |forum|
      forum.recordings.each_key do |video_id|
        PrepareElectionForumCaptionsJob.perform_later(forum.id, video_id) unless PrepareElectionForumCaptionsJob.ready?(video_id)
      end
    end
  end
end
