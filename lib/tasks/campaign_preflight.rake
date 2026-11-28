namespace :council_profiles do
  desc "Preview spring council profile comparisons for an inclusive range of meeting dates, without dispatching jobs"
  task :comparison_preview, [ :from, :through ] => :environment do |_task, args|
    names = ResidentContent::CouncilElection::GUIDE.fetch("terms_ending").keys
    members = names.map { |name| Member.find_by!(name: name) }
    puts JSON.pretty_generate(Campaigns::ComparisonPreview.call(members: members,
      from: Date.iso8601(args.fetch(:from)), through: Date.iso8601(args.fetch(:through))))
  end

  desc "Show a read-only campaign cost estimate; does not authorize or dispatch AI"
  task :campaign_preflight, [ :source_id ] => :environment do |_task, args|
    source = CampaignSource.find(Integer(args.fetch(:source_id), 10))
    puts JSON.pretty_generate({ source_id: source.id, version_id: source.current_version.id,
      preflight: Campaigns::CostPreflight.call(source.current_version) })
  end
end

namespace :council_profiles do
  desc "List current platform review requests and their funding estimates without dispatch"
  task platform_preflight: :environment do
    Member.where(id: CampaignStatement.where(status: "accepted", excluded_at: nil).select(:member_id)).find_each do |member|
      CampaignStatement.current_for(member).group_by { |s| s.campaign_source_version.election_on }.each_value do |rows|
        selection = Campaigns::PlatformSelection.new(rows)
        stage = selection.current || selection.prepare
        next unless stage
        puts({ member: member.name, election: stage.election_on, request: stage.input_key, status: stage.status,
          positions: stage.groups&.size, estimate: Campaigns::CostPreflight.for_stage(stage) }.to_json)
      end
    end
  end

  desc "Apply a source-checked platform correction to the exact current request from a local JSON file"
  task :correct_platform, [ :input_key, :file ] => :environment do |_task, args|
    stage = CampaignPlatformReview.find_by!(input_key: args.fetch(:input_key))
    rows = CampaignStatement.current_for(stage.member).select { |row| row.campaign_source_version.election_on == stage.election_on }
    Campaigns::PlatformSelection.new(rows).publish!(stage, File.read(args.fetch(:file)), correction: true)
    puts "Retained #{stage.groups.size} positions for #{stage.member.name}."
  end
end
