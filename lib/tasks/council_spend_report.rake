namespace :council_profiles do
  desc "Read monthly council reservations and usage; never authorizes or dispatches AI"
  task :spend_report, [ :month ] => :environment do |_task, args|
    date = args[:month] ? Date.strptime(args[:month], "%Y-%m") : Date.current
    puts JSON.pretty_generate(CouncilProfiles::SpendReport.call(date: date))
  end
end
