namespace :council_profiles do
  desc "Show a read-only campaign cost estimate; does not authorize or dispatch AI"
  task :campaign_preflight, [ :source_id ] => :environment do |_task, args|
    source = CampaignSource.find(Integer(args.fetch(:source_id), 10))
    puts JSON.pretty_generate({ source_id: source.id, version_id: source.current_version.id,
      preflight: Campaigns::CostPreflight.call(source.current_version) })
  end
end
