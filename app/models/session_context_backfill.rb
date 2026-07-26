# Derives ip_prefix and device_fingerprint for session rows that have neither,
# from the ip_address and user_agent already stored on them.
#
# Extracted from the migration rather than written inline so that its test runs
# this exact code. A test that re-implements the backfill's SQL passes whatever
# the migration does, which would leave the most lockout-critical step in this
# project with no real regression test.
#
# Raw SQL through the connection, not the Session model: a migration has to keep
# working when the model moves on. NetworkPrefix and DeviceFingerprint are pure
# functions with no schema coupling, so calling them is safe.
class SessionContextBackfill
  def self.run!
    connection = ActiveRecord::Base.connection
    rows = connection.select_all("SELECT id, ip_address, user_agent FROM sessions WHERE ip_prefix IS NULL AND device_fingerprint IS NULL")

    rows.each do |row|
      connection.exec_update(<<~SQL.squish, "Backfill session context", query_attributes(row))
        UPDATE sessions
        SET ip_prefix = $1,
            device_fingerprint = $2,
            reauthenticated_at = created_at
        WHERE id = $3
      SQL
    end

    rows.length
  end

  def self.query_attributes(row)
    [
      ActiveRecord::Relation::QueryAttribute.new("ip_prefix", NetworkPrefix.for(row["ip_address"]), ActiveRecord::Type::String.new),
      ActiveRecord::Relation::QueryAttribute.new("device_fingerprint", DeviceFingerprint.for(row["user_agent"]), ActiveRecord::Type::String.new),
      ActiveRecord::Relation::QueryAttribute.new("id", row["id"], ActiveRecord::Type::Integer.new)
    ]
  end
  private_class_method :query_attributes
end
