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
