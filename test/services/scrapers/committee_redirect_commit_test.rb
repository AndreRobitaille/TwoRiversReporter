require "test_helper"
require Rails.root.join("db/migrate/20261030124500_rename_committee_on_agenda_to_committee_on_aging.rb")

class Scrapers::CommitteeRedirectCommitTest < ActiveJob::TestCase
  # These assertions need a real outer commit visible to another connection.
  self.use_transactional_tests = false

  SOURCE_PATH = "/committees/committee-on-agenda"

  setup do
    @previous_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
    @good = Committee.create!(name: "Committee on Aging")
    @bad = Committee.create!(name: "Committee On Agenda")
    @meeting = Meeting.create!(body_name: "Committee On Agenda", committee: @bad,
      starts_at: Time.zone.parse("2026-11-02 08:30:00"),
      detail_page_url: "https://www.two-rivers.org/bc-coa/page/committee-agenda")
    clear_enqueued_jobs
  end

  teardown do
    Redirect.where(source_path: SOURCE_PATH).delete_all
    Meeting.where(id: @meeting&.id).delete_all
    Committee.where(id: [ @good&.id, @bad&.id ]).delete_all
    Rails.cache = @previous_cache
  end

  test "inserted redirect is visible after the migration commits" do
    assert_equal "redirects/lookup_map", Redirect::CACHE_KEY
    assert_nil Redirect.lookup(SOURCE_PATH)
    assert Rails.cache.exist?(Redirect::CACHE_KEY)

    assert_no_enqueued_jobs { run_correction }

    assert_committed_redirect
  end

  test "updated redirect replaces a cached destination and preserves hit history" do
    now = Time.current
    Redirect.insert!({ source_path: SOURCE_PATH, destination: "/stale", status_code: 302,
      hits: 4, created_at: now, updated_at: now })
    assert_equal "/stale", Redirect.lookup(SOURCE_PATH)[:destination]
    assert_equal 302, Redirect.lookup(SOURCE_PATH)[:status_code]

    assert_no_enqueued_jobs { run_correction }

    assert_equal 4, Redirect.find_by!(source_path: SOURCE_PATH).hits
    assert_committed_redirect
  end

  test "a concurrent precommit lookup cannot leave the committed redirect hidden" do
    assert_nil Redirect.lookup(SOURCE_PATH)

    assert_no_enqueued_jobs do
      ActiveRecord::Base.transaction do
        run_correction
        # Wait for a separate request connection while the writer is uncommitted.
        before_commit = Thread.new do
          ActiveRecord::Base.connection_pool.with_connection { Redirect.lookup(SOURCE_PATH) }
        end.value
        assert_nil before_commit, "another connection must not see an uncommitted redirect"
      end
    end

    assert_equal destination, Redirect.find_by!(source_path: SOURCE_PATH).destination
    assert_committed_redirect
  end

  test "rollback preserves the cached map and original records" do
    assert_nil Redirect.lookup(SOURCE_PATH)
    original_map = Rails.cache.read(Redirect::CACHE_KEY)

    assert_no_enqueued_jobs do
      ActiveRecord::Base.transaction do
        run_correction
        raise ActiveRecord::Rollback
      end
    end

    assert Rails.cache.exist?(Redirect::CACHE_KEY), "rollback must not run the cache invalidation"
    assert_equal original_map, Rails.cache.read(Redirect::CACHE_KEY)
    assert_not Redirect.exists?(source_path: SOURCE_PATH)
    assert_equal "Committee On Agenda", @meeting.reload.body_name
    assert_equal @bad.id, @meeting.committee_id
    assert Committee.exists?(@bad.id)
  end

  private

  def run_correction
    migration = RenameCommitteeOnAgendaToCommitteeOnAging.new
    migration.verbose = false
    ActiveRecord::Base.transaction(requires_new: true) { migration.up }
  end

  def destination
    "/committees/#{@good.slug}"
  end

  def assert_committed_redirect
    hit = Redirect.lookup(SOURCE_PATH)
    assert_equal destination, hit && hit[:destination]
    assert_equal 301, hit && hit[:status_code]
    client = ActionDispatch::Integration::Session.new(Rails.application)
    client.get SOURCE_PATH
    assert_equal 301, client.response.status
    assert_equal destination, client.response.location
  end
end
