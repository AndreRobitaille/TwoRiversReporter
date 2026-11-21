namespace :council_profiles do
  desc "Read monthly council reservations and usage; never authorizes or dispatches AI"
  task :spend_report, [ :month ] => :environment do |_task, args|
    date = args[:month] ? Date.strptime(args[:month], "%Y-%m") : Date.current
    puts JSON.pretty_generate(CouncilProfiles::SpendReport.call(date: date))
  end
end

namespace :council_profiles do
  desc "Activate the standing monthly promise comparison allowance for new Council records"
  task enable_nightly: :environment do
    actor = User.find(ENV.fetch("ACTOR_ID"))
    council = Committee.resolve("City Council") || raise("Council committee missing")
    date = Date.current
    policy = { "starting_on" => date.iso8601, "model" => Ai::OpenAiService.model_for_tier(PromptTemplate.find_by!(key: "match_campaign_actions").model_tier),
      "estimate_method" => "utf8_bytes_plus_1024", "daily_limit_microusd" => 10_000_000, "request_limit_microusd" => 1_000_000,
      "max_requests_per_day" => 100, "max_concurrent" => 2, "max_input_tokens" => 200_000, "max_output_tokens" => 8_000,
      "issue_sources" => { "starting_on" => date.iso8601, "committee_ids" => [ council.id ],
        "document_types" => CouncilProfiles::LiveSources::TYPES, "extract_packets" => false } }
    month = CouncilAiBudgetMonth.find_or_create_by!(budget_month: date.beginning_of_month) do |row|
      row.assign_attributes(actor: actor, authorized_at: Time.current, authorization_basis: "Standing authorization for monthly promise comparisons",
        live_actions: policy, auto_renew: true, limit_microusd: 10_000_000)
    end
    raise "Different existing monthly authorization" unless month.actor == actor && month.auto_renew? && !month.revoked_at &&
      month.limit_microusd == 10_000_000 && month.live_actions.except("starting_on", "issue_sources") == policy.except("starting_on", "issue_sources") &&
      month.live_actions.fetch("issue_sources").except("starting_on") == policy.fetch("issue_sources").except("starting_on")
    puts "Standing monthly promise comparisons enabled from #{month.live_actions.fetch('starting_on')}"
  end
end
