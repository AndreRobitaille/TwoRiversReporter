# lib/tasks/resummarize.rake
#
# Re-summarize all meetings with extracted minutes using the current prompts.
# Does NOT re-extract topics, votes, or members — only re-runs the summarization
# pipeline: analyze_meeting_content → analyze_topic_summary per topic →
# update_resident_impact_from_ai → PruneHollowAppearancesJob →
# ExtractKnowledgeJob → GenerateTopicBriefingJob.
#
# Usage (on prod via kamal):
#   bin/kamal app exec "bin/rails resummarize:all"
#   bin/kamal app exec "bin/rails resummarize:status"

namespace :resummarize do
  desc "Enqueue SummarizeMeetingJob for all meetings with extracted minutes"
  task all: :environment do
    meetings = Meeting.joins(:meeting_documents)
      .where(meeting_documents: { document_type: "minutes_pdf" })
      .where("meeting_documents.extracted_text IS NOT NULL AND meeting_documents.extracted_text != ''")
      .distinct
      .order(:starts_at) # oldest first so newer impact scores overwrite

    count = meetings.count
    puts "Enqueuing SummarizeMeetingJob for #{count} meetings with extracted minutes..."
    puts "Date range: #{meetings.first&.starts_at&.to_date} to #{meetings.last&.starts_at&.to_date}"
    puts ""

    topic_pairs = 0
    meetings.each_with_index do |meeting, i|
      topics_count = meeting.topics.approved.distinct.count
      topic_pairs += topics_count
      SummarizeMeetingJob.perform_later(meeting.id)

      if (i + 1) % 10 == 0 || (i + 1) == count
        puts "  Enqueued #{i + 1}/#{count}: #{meeting.body_name} (#{meeting.starts_at&.to_date}) [#{topics_count} topics]"
      end
    end

    puts ""
    puts "Done. #{count} SummarizeMeetingJob enqueued (#{topic_pairs} topic-meeting pairs)."
    puts "Each job cascades to: PruneHollowAppearancesJob + ExtractKnowledgeJob + GenerateTopicBriefingJob per topic."
    puts ""
    puts "Monitor with: bin/rails resummarize:status"
    puts "Or via kamal: bin/kamal app exec 'bin/rails resummarize:status'"
  end

  desc "Show resummarize progress"
  task status: :environment do
    # Count meetings with new-format summaries (have activity_level in item_details)
    total_minutes = Meeting.joins(:meeting_documents)
      .where(meeting_documents: { document_type: "minutes_pdf" })
      .where("meeting_documents.extracted_text IS NOT NULL AND meeting_documents.extracted_text != ''")
      .distinct.count

    new_format = MeetingSummary.where("generation_data IS NOT NULL")
      .where("generation_data::text LIKE '%activity_level%'")
      .select(:meeting_id).distinct.count

    # Job queue state
    pending = SolidQueue::Job.where(finished_at: nil).count rescue "N/A"
    failed = SolidQueue::FailedExecution.count rescue "N/A"

    puts ""
    puts "=== Resummarize Progress ==="
    puts "Minutes-backed meetings: #{total_minutes}"
    puts "With new-format summary: #{new_format}"
    puts "Remaining:               #{total_minutes - new_format}"
    puts ""
    puts "Queue: #{pending} pending, #{failed} failed"

    if pending.is_a?(Integer) && pending > 0
      puts ""
      puts "Pending job breakdown:"
      SolidQueue::Job.where(finished_at: nil)
        .group(:class_name).count
        .sort_by { |_, v| -v }
        .each { |name, n| puts "  #{name}: #{n}" }
    end

    if failed.is_a?(Integer) && failed > 0
      puts ""
      puts "Recent failures:"
      SolidQueue::FailedExecution.order(created_at: :desc).limit(5).each do |f|
        job = f.job
        puts "  #{job.class_name} (#{job.arguments.first(80)}): #{f.error.to_s.truncate(120)}"
      end
    end

    # Impact score distribution for approved topics
    puts ""
    puts "Impact score distribution (approved topics):"
    Topic.approved.group(:resident_impact_score).count.sort.each do |score, n|
      label = score.nil? ? "nil" : score.to_s
      puts "  #{label}: #{n}"
    end

    # Homepage-eligible count
    top_stories = Topic.approved
      .where("resident_impact_score >= 4")
      .where("last_activity_at > ?", 30.days.ago).count
    wire = Topic.approved
      .where("resident_impact_score >= 2")
      .where("last_activity_at > ?", 30.days.ago).count
    puts ""
    puts "Homepage-eligible (30d window): #{top_stories} top stories (>=4), #{wire} wire (>=2)"
    puts ""
  end
end
