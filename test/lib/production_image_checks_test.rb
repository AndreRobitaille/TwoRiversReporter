require "test_helper"

class ProductionImageChecksTest < ActiveSupport::TestCase
  self.use_transactional_tests = false

  class ProbeJob < ApplicationRecord
  end

  setup do
    @table = "image_probe_jobs_#{SecureRandom.hex(6)}"
    ProbeJob.table_name = @table
    ApplicationRecord.connection.create_table(@table) do |table|
      table.string :active_job_id
      table.datetime :finished_at
    end
    ProbeJob.reset_column_information
  end

  teardown do
    ApplicationRecord.connection.drop_table(@table, if_exists: true)
  end

  test "observes completion committed on another connection while query caching is enabled" do
    job = ProbeJob.create!(active_job_id: "synthetic-cleanup")
    finish = -> {
      Thread.new do
        ApplicationRecord.connection_pool.with_connection do
          ProbeJob.where(id: job.id).update_all(finished_at: Time.current)
        end
      end.value
    }

    ProbeJob.cache do
      assert_nil ProbeJob.find_by(active_job_id: job.active_job_id).finished_at
      assert ProductionImageChecks.job_completed?(job.active_job_id, jobs: ProbeJob, attempts: 2, pause: finish)
    end
    assert ProbeJob.find(job.id).finished_at
  end

  test "missing and unfinished jobs do not count as completed" do
    job = ProbeJob.create!(active_job_id: "unfinished")
    refute ProductionImageChecks.job_completed?("absent", jobs: ProbeJob, attempts: 1, pause: -> { })
    refute ProductionImageChecks.job_completed?(job.active_job_id, jobs: ProbeJob, attempts: 1, pause: -> { })
  end
end
