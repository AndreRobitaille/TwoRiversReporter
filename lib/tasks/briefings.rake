namespace :briefings do
  desc "Generate full briefings for all approved topics with existing summaries"
  task generate: :environment do
    topics = Topic.approved.joins(:topic_summaries).distinct.where.missing(:topic_briefing)

    puts "Found #{topics.count} topics needing briefings"

    topics.find_each do |topic|
      latest_summary = topic.topic_summaries.joins(:meeting).order("meetings.starts_at DESC").first
      next unless latest_summary

      puts "  Enqueuing briefing for: #{topic.canonical_name} (meeting: #{latest_summary.meeting.body_name})"
      Topics::GenerateTopicBriefingJob.perform_later(
        topic_id: topic.id,
        meeting_id: latest_summary.meeting_id
      )
    end

    puts "Done. Jobs enqueued — run bin/jobs to process."
  end
end
