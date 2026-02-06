module Admin
  class JobsController < BaseController
    def show
      # Queue statistics
      @ready_count = SolidQueue::ReadyExecution.count
      @scheduled_count = SolidQueue::ScheduledExecution.count
      @claimed_count = SolidQueue::ClaimedExecution.count
      @failed_count = SolidQueue::FailedExecution.count

      # Jobs by type (ready + scheduled + claimed = pending)
      @jobs_by_class = SolidQueue::Job
        .where(finished_at: nil)
        .group(:class_name)
        .count
        .sort_by { |_, count| -count }

      # Recently completed jobs (last 50)
      @recent_completed = SolidQueue::Job
        .where.not(finished_at: nil)
        .order(finished_at: :desc)
        .limit(50)

      # Failed jobs with error details
      @failed_jobs = SolidQueue::FailedExecution
        .includes(:job)
        .order(created_at: :desc)
        .limit(50)

      # Active workers
      @workers = SolidQueue::Process.where(kind: "Worker").order(last_heartbeat_at: :desc)
      @dispatchers = SolidQueue::Process.where(kind: "Dispatcher").order(last_heartbeat_at: :desc)

      # Check if any worker is alive (heartbeat within last 60 seconds)
      @worker_alive = @workers.any? { |w| w.last_heartbeat_at > 60.seconds.ago }
    end

    def retry_failed
      failed = SolidQueue::FailedExecution.find(params[:id])
      job = failed.job

      # Re-enqueue by creating a new ready execution
      SolidQueue::ReadyExecution.create!(
        job_id: job.id,
        queue_name: job.queue_name,
        priority: job.priority
      )
      failed.destroy!

      redirect_to admin_jobs_path, notice: "Job #{job.class_name} re-queued for retry."
    end

    def retry_all_failed
      count = 0
      SolidQueue::FailedExecution.find_each do |failed|
        job = failed.job
        SolidQueue::ReadyExecution.create!(
          job_id: job.id,
          queue_name: job.queue_name,
          priority: job.priority
        )
        failed.destroy!
        count += 1
      end

      redirect_to admin_jobs_path, notice: "Re-queued #{count} failed job(s) for retry."
    end

    def discard_failed
      failed = SolidQueue::FailedExecution.find(params[:id])
      job = failed.job
      failed.destroy!
      job.destroy!

      redirect_to admin_jobs_path, notice: "Failed job discarded."
    end

    def clear_completed
      # Clear failed executions and their jobs
      failed_job_ids = SolidQueue::FailedExecution.pluck(:job_id)
      failed_count = SolidQueue::FailedExecution.delete_all
      SolidQueue::Job.where(id: failed_job_ids).delete_all

      # Clear completed jobs
      completed_count = SolidQueue::Job.where.not(finished_at: nil).delete_all

      redirect_to admin_jobs_path, notice: "Cleared #{completed_count} completed and #{failed_count} failed job(s)."
    end
  end
end
