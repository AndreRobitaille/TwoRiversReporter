module CouncilHistory
  class Coverage
    # The nightly job revisits recently changed listings. Older official links
    # are kept so a later correction in the archive can also clear a gap.
    def self.refresh!(full: false)
      saved = SiteSetting.instance.council_coverage || {}
      return if !full && saved["listings"].blank?
      from = Batch::FIRST
      since = full ? from : [ Date.iso8601(saved.fetch("through")) - 14.days, from ].max
      older = full ? [] : saved.fetch("listings").select { |r| Time.iso8601(r.fetch("starts_at")).in_time_zone.to_date < since }
      recent = Inventory.new(from: since, through: Date.current, body: "council").listings
      listings = older + recent.select { |row| Time.iso8601(row.fetch("starts_at")) <= Time.current }
      rows = Inventory.review(listings)
      through = rows.reject { |row| row.fetch("disposition").in?(%w[cancelled duplicate]) }
        .map { |row| Time.iso8601(row.fetch("starts_at")).in_time_zone.to_date }.max
      raise "City calendar returned no held Council listings" unless through
      publish!(rows, from: from, through: through)
    end

    def self.publish!(rows, from:, through:)
      confirmed = rows.reject { |r| r.fetch("disposition").in?(%w[cancelled duplicate]) }
      gaps = confirmed.filter_map do |row|
        reason = case row.fetch("disposition")
        when "source_unavailable" then "The city meeting page could not be verified"
        when "ambiguous_minutes" then "The city lists multiple minutes files requiring review"
        when "different_minutes" then "The city lists a different minutes file. The archived version needs review."
        when "ambiguous_identity" then "Meeting identity needs review"
        when "no_minutes_link" then "Official minutes have not been located"
        when "fetch_minutes" then "Minutes await processing"
        when "usable"
          if row.fetch("votes").zero? && row["vote_status"] != "empty"
            "Voting record needs review"
          elsif row.fetch("attendance").zero? && row["attendance_status"] != "empty"
            "Attendance has not been recorded"
          end
        end
        { "date" => Time.iso8601(row.fetch("starts_at")).in_time_zone.to_date.iso8601,
          "title" => row.fetch("title"), "url" => row.fetch("url"), "reason" => reason } if reason
      end
      snapshot = { "from" => from.iso8601, "through" => through.iso8601, "checked_on" => Date.current.iso8601,
        "meetings" => confirmed.size, "usable" => confirmed.count { |r| r.fetch("disposition") == "usable" }, "gaps" => gaps,
        "listings" => rows.map { |r| r.slice("title", "starts_at", "url", "documents", "detail_minutes") } }
      setting = SiteSetting.find_or_create_by!(singleton_guard: 0)
      setting.update!(council_coverage: snapshot) unless setting.council_coverage == snapshot
      snapshot
    end
  end
end
