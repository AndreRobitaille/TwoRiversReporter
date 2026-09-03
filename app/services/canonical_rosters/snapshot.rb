module CanonicalRosters
  Snapshot = Data.define(
    :key,
    :committee_name,
    :membership_source,
    :position_source,
    :source_url,
    :managed_roles,
    :entries
  )
end
