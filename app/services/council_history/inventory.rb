module CouncilHistory
  # The calendar listing itself links to the official documents, including
  # minutes for some events whose separate detail page is no longer reachable.
  class Inventory
    CITY = Scrapers::DiscoverMeetingsJob::MEETINGS_URL
    COLUMNS = { "minutes_pdf" => "minutes", "agenda_html" => "agendas", "agenda_pdf" => "agendas", "packet_pdf" => "packets" }.freeze

    def initialize(from:, through:, body: nil)
      @from, @through, @body = from, through, body
      raise ArgumentError, "Invalid meeting window" unless from <= through && through <= Date.current
    end

    def listings
      filters = {}
      { "date_filter" => @from, "date_filter_1" => @through }.each do |key, date|
        %w[year month day].each { |part| filters["#{key}[value][#{part}]"] = date.public_send(part) }
      end
      agent = Mechanize.new
      agent.user_agent_alias = "Mac Safari"
      url = "#{CITY}?#{filters.to_query}"
      seen = Set.new
      rows = []
      while url
        raise "Calendar pagination loop" unless seen.add?(url)
        page = agent.get(url)
        raise "City calendar unavailable" unless page.at_css("table.views-table, .view-calendar .view-empty")
        rows.concat(parse(page))
        link = page.at_css(".pager-next a")
        break unless link
        next_page = URI.join(CITY, link["href"])
        raise "Unexpected calendar pagination" unless next_page.scheme == "https" && next_page.host == "www.two-rivers.org" && next_page.path == "/meetings"
        url = next_page.to_s
      end
      rows
    end

    def parse(page)
      page.css("table.views-table tbody tr").filter_map do |row|
        starts_at = Time.iso8601(row.at_css(".views-field-field-calendar-date span")["content"]).in_time_zone
        next unless starts_at.to_date.between?(@from, @through)
        title = row.at_css(".views-field-title").text.squish
        next if @body.present? && !title.downcase.include?(@body.downcase)
        detail = URI.join(CITY, row.at_css(".views-field-view-node a")["href"]).to_s
        raise "Unexpected calendar detail link" unless URI(detail).host == "www.two-rivers.org" && URI(detail).scheme == "https"
        title = Scrapers::CommitteeOnAgendaName.correct(title, detail)
        documents = COLUMNS.filter_map do |type, column|
          links = row.css(".views-field-field-#{column} a[href]").filter_map do |anchor|
            uri = URI.join(CITY, anchor["href"])
            uri.to_s if uri.scheme == "https" && uri.host.in?(%w[mccmeetings.blob.core.usgovcloudapi.net meetings.municode.com www.two-rivers.org])
          end
          url = links.find { |href| href.downcase.include?(".pdf") == type.end_with?("_pdf") }
          [ type, url ] if url
        end.to_h
        { "starts_at" => starts_at.iso8601, "title" => title, "url" => detail, "documents" => documents }
      end
    end

    def self.destination(row)
      starts_at = Time.iso8601(row.fetch("starts_at"))
      url = row.fetch("url")
      matches = Meeting.where(starts_at: starts_at)
      exact = matches.where(detail_page_url: url).to_a
      return [ nil, "ambiguous_identity" ] if exact.many?
      return [ exact.first, nil ] if exact.one?
      # Legacy rows sometimes retained the official minutes link as their detail URL.
      urls = row.fetch("documents").values_at("minutes_pdf", "packet_pdf").compact
      if urls.any?
        sources = matches.joins(:meeting_documents).where(meeting_documents: { source_url: urls }).distinct.to_a
        return [ nil, "ambiguous_identity" ] if sources.many?
        return [ sources.first, nil ] if sources.one?
      end
      committee = Committee.resolve(row.fetch("title"))
      conflict = matches.any? { |m| (committee && m.committee_id == committee.id) ||
        Meeting.normalized_body_name(m.body_name) == Meeting.normalized_body_name(row.fetch("title")) }
      [ nil, ("ambiguous_identity" if conflict || Meeting.where(detail_page_url: url).exists?) ]
    end

    def self.review(rows)
      seen = Set.new
      rows.map do |row|
        meeting, conflict = destination(row)
        url = row.fetch("documents")["minutes_pdf"]
        minutes = meeting&.latest_document("minutes_pdf")
        disposition = if row.fetch("title").match?(/\bcancell?ed\b|\bno quorum\b/i) || meeting&.cancelled?
          "cancelled"
        elsif !seen.add?([ row.fetch("starts_at"), row.fetch("url") ]) || (meeting && !seen.add?(meeting.id))
          "duplicate"
        elsif conflict
          conflict
        elsif minutes&.extracted_text.present?
          url && minutes.source_url.present? && url != minutes.source_url ? "different_minutes" : "usable"
        elsif url
          "fetch_minutes"
        else
          "no_minutes_link"
        end
        row.merge("meeting_id" => meeting&.id, "disposition" => disposition,
          "topics_status" => meeting&.processing_state&.fetch("topics_extraction_status", nil),
          "vote_status" => meeting&.processing_state&.fetch("votes_extraction_status", nil),
          "votes" => meeting&.motions&.joins(:votes)&.count || 0,
          "attendance" => meeting&.meeting_attendances&.count || 0,
          "attendance_status" => meeting&.processing_state&.fetch("committee_members_extraction_status", nil),
          "recaps" => meeting&.meeting_summaries&.published&.where(summary_type: "minutes_recap")&.count || 0)
      end
    end
  end
end
