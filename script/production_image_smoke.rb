# Runs inside the production image, only against CI's disposable databases.
abort "Synthetic CI database required" unless ENV["DB_HOST"] == "db" && ENV["TWO_RIVERS_REPORTER_DATABASE_PASSWORD"] == "ci-only"

Rails.application.eager_load!
{ "primary" => ApplicationRecord, "cache" => SolidCache::Record,
  "queue" => SolidQueue::Record, "cable" => SolidCable::Record }.each do |name, record|
  configuration = record.connection_pool.db_config
  abort "Wrong #{name} database" unless configuration.name == name
  abort "#{name} database unavailable" unless record.connection.select_value("SELECT 1") == 1
  puts "#{name}: #{configuration.database} reachable"
end

SiteSetting.find_or_create_by!(singleton_guard: 0) { |setting| setting.access_mode = "open" }
abort "Persisted settings unavailable" unless SiteSetting.access_mode == "open"
Rails.cache.write("production-image-smoke", "synthetic", expires_in: 1.minute)
abort "Solid Cache round trip failed" unless Rails.cache.read("production-image-smoke") == "synthetic"
job = ExpiredAuthRecordsCleanupJob.perform_later
abort "Job enqueue failed" unless job.successfully_enqueued?
completed = false
30.times do
  queued = SolidQueue::Job.find_by(active_job_id: job.job_id)
  if queued&.finished_at
    completed = true
    break
  end
  sleep 1
end
abort "Embedded Solid Queue worker did not complete the synthetic cleanup job" unless completed
puts "Persisted primary setting, Solid Cache round trip and embedded worker completion passed."
