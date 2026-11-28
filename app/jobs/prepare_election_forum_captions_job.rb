class PrepareElectionForumCaptionsJob < ApplicationJob
  queue_as :default
  limits_concurrency to: 1, key: ->(_forum_id, video_id) { video_id }, on_conflict: :discard

  def self.ready?(video_id)
    url = ElectionForum.video_url(video_id)
    Campaigns::ElectionBackfill.caption_path({ "kind" => "forum", "url" => url }) || CampaignSource.exists?(source_url: url)
  end

  def perform(forum_id, video_id)
    forum = ElectionForum.find(forum_id)
    return unless forum.recordings.key?(video_id)
    return if self.class.ready?(video_id)

    unless system(Rails.root.join("bin/prepare-forum-captions").to_s, video_id)
      forum.with_lock do
        recording = forum.recordings.fetch(video_id).merge("needs_captions" => true)
        forum.update!(recordings: forum.recordings.merge(video_id => recording))
      end
      Rails.logger.info("Captions for forum #{video_id} are unavailable. The election desk accepts a local transcript.")
    end
  end
end
