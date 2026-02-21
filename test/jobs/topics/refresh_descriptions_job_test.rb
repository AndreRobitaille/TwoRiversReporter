require "test_helper"

class Topics::RefreshDescriptionsJobTest < ActiveJob::TestCase
  test "enqueues GenerateDescriptionJob for stale descriptions" do
    stale = Topic.create!(name: "stale topic", status: "approved",
      description: "Old AI text", description_generated_at: 91.days.ago)
    _fresh = Topic.create!(name: "fresh topic", status: "approved",
      description: "Recent AI text", description_generated_at: 10.days.ago)

    Topics::RefreshDescriptionsJob.perform_now

    assert_enqueued_with(job: Topics::GenerateDescriptionJob, args: [stale.id])
    assert_enqueued_jobs 1, only: Topics::GenerateDescriptionJob
  end

  test "enqueues for blank descriptions but skips admin-edited" do
    blank = Topic.create!(name: "blank topic", status: "approved",
      description: nil, description_generated_at: nil)
    _admin_edited = Topic.create!(name: "admin topic", status: "approved",
      description: "Admin wrote this", description_generated_at: nil)

    Topics::RefreshDescriptionsJob.perform_now

    assert_enqueued_with(job: Topics::GenerateDescriptionJob, args: [blank.id])
    assert_enqueued_jobs 1, only: Topics::GenerateDescriptionJob
  end

  test "skips non-approved topics" do
    _proposed = Topic.create!(name: "proposed topic", status: "proposed",
      description: nil, description_generated_at: nil)

    Topics::RefreshDescriptionsJob.perform_now

    assert_enqueued_jobs 0, only: Topics::GenerateDescriptionJob
  end
end
