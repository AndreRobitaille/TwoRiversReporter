class ProductionImageChecks
  def self.job_completed?(job_id, jobs: SolidQueue::Job, attempts: 30, pause: -> { sleep 1 })
    attempts.times do
      # Rails runners enable query caching. Completion is written by another process.
      job = jobs.uncached { jobs.find_by(active_job_id: job_id) }
      return true if job&.finished_at

      pause.call
    end
    false
  end
end
