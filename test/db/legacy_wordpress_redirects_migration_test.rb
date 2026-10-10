require "test_helper"
require Rails.root.join("db/migrate/20261003180000_add_legacy_wordpress_redirects")

class LegacyWordpressRedirectsMigrationTest < ActiveSupport::TestCase
  test "seeding preserves existing redirects and is idempotent" do
    existing = Redirect.create!(source_path: "/contact", destination: "/custom-contact", status_code: 302)
    migration = AddLegacyWordpressRedirects.new

    migration.up
    migration.up

    assert_equal "/custom-contact", existing.reload.destination
    assert_equal 302, existing.status_code
    assert_equal AddLegacyWordpressRedirects::PATHS.size, Redirect.where(source_path: AddLegacyWordpressRedirects::PATHS.keys).count
  end

  test "rollback refuses to delete existing or customized redirects" do
    existing = Redirect.create!(source_path: "/contact", destination: "/custom-contact", status_code: 302)
    migration = AddLegacyWordpressRedirects.new
    migration.up
    customized = Redirect.find_by!(source_path: "/city-info")
    customized.update!(destination: "/custom-city-info", status_code: 307)

    assert_raises(ActiveRecord::IrreversibleMigration) { migration.down }

    assert_equal "/custom-contact", existing.reload.destination
    assert_equal "/custom-city-info", customized.reload.destination
    assert_equal 307, customized.status_code
  end
end
