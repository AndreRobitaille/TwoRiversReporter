namespace :topics do
  desc "Surgically rerun topic extraction and downstream topic analysis for one meeting"
  task :reanalyze_meeting, [ :meeting_id ] => :environment do |_task, args|
    meeting_id = args[:meeting_id].presence || ENV["MEETING_ID"]
    abort "Usage: bin/rails 'topics:reanalyze_meeting[MEETING_ID]'" if meeting_id.blank?

    result = Topics::MeetingReanalysisService.new(meeting_id).call
    puts "Homepage top story candidate ids: #{result.selector_ids.inspect}"
    puts "Homepage wire candidate ids: #{result.wire_ids.inspect}"
    puts "Topic 189 on homepage: #{(result.selector_ids | result.wire_ids).include?(189)}"
  end
end
