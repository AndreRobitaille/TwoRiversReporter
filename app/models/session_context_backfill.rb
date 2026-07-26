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
      connection.execute(<<~SQL.squish)
        UPDATE sessions
        SET ip_prefix = #{connection.quote(NetworkPrefix.for(row["ip_address"]))},
            device_fingerprint = #{connection.quote(DeviceFingerprint.for(row["user_agent"]))},
            reauthenticated_at = created_at
        WHERE id = #{Integer(row["id"])}
      SQL
    end

    rows.length
  end
end
