class ElectionForum < ApplicationRecord
  def self.video_url(video_id)
    "https://www.youtube.com/watch?v=#{video_id}"
  end

  def recording_leads
    recordings.sort_by { |_id, video| video.fetch("started_at") }.to_h do |video_id, video|
      title = video.fetch("title")
      [ "forum_#{video_id}", { "kind" => "forum", "short_title" => title, "title" => title,
        "preparing_captions" => !video["needs_captions"], "url" => self.class.video_url(video_id), "published_on" => held_on.iso8601, "publisher" => organizer } ]
    end
  end
end
