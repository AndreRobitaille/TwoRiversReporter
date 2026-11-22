namespace :council_profiles do
  desc "Recover exact forum quotations from a saved response without another extraction call"
  task :recover_forum_quotes, [ :source_id, :actor_id ] => :environment do |_task, args|
    source = CampaignSource.find(Integer(args.fetch(:source_id), 10))
    actor = User.find(Integer(args.fetch(:actor_id), 10))
    extraction = Campaigns::RecoverForumQuotes.call(source, actor: actor)
    puts JSON.pretty_generate({ source_id: source.id, version_id: source.current_version.id,
      extraction_id: extraction.id, counts: extraction.data.fetch("counts"),
      topic_matching_status: source.current_version.topic_matching&.status })
  end
end
