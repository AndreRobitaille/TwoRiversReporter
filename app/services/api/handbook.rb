module Api
  class Handbook
    FILTER_NAMES = %w[q lifecycle from to committee_id status updated_since sort limit offset document_id checksum].freeze
    ENDPOINTS = {
      "/home" => "Current top stories, wire, and upcoming council meetings",
      "/topics" => "Approved topics; research search, lifecycle, updated_since, and sort filters",
      "/topics/:id" => "Resident topic briefing and links to history/decisions",
      "/topics/:id/appearances" => "Paginated topic history and meeting appearances",
      "/topics/:id/decisions" => "Paginated motions and votes linked to the topic",
      "/meetings" => "Canonical meetings; research search, date/body/status filters, updated_since, and sort",
      "/meetings/:id" => "Meeting details and preferred generated summary",
      "/meetings/:id/agenda_items" => "Substantive agenda items and displayed item analysis",
      "/meetings/:id/documents" => "Latest document metadata and original source links",
      "/meetings/:id/transcript" => "Stored transcript text, recording link, and source quality",
      "/committees" => "Resident committee directory",
      "/committees/:slug" => "Committee description, public roster, and recent topics",
      "/officials" => "Public civic officials, not site accounts",
      "/officials/:id" => "Public positions, memberships, and attendance",
      "/officials/:id/votes" => "Paginated resident-visible voting record"
    }.freeze

    def initialize(base_url:)
      @base_url = base_url
    end

    def to_h
      { version: "v1", scope: "read_resident_content", methods: %w[GET HEAD],
        authentication: "Send your API key in Authorization: Bearer <key>. Browser cookies do not authenticate this API.",
        workflows: {
          recent_updates: {
            meetings: "#{@base_url}/api/v1/meetings?sort=updated",
            topics: "#{@base_url}/api/v1/topics?sort=updated",
            incremental_filter: "updated_since accepts an inclusive ISO 8601 timestamp with timezone; it defaults sorting to updated.",
            timestamps: "updated_at includes child documents/analysis, independently of meeting dates and topic last_activity_at. Separate document/analysis timestamps and availability flags explain what to fetch.",
            follow_up: "Follow links.documents, links.agenda_items, and links.transcript from a meeting; follow links.api from a topic.",
            polling: "Follow links.next, overlap successive polls and deduplicate by resource ID and updated_at. Live offset pages can shift; this is current content discovery, not an event/deletion log."
          },
          research: {
            meetings: "#{@base_url}/api/v1/meetings?q=stormwater",
            topics: "#{@base_url}/api/v1/topics?q=stormwater",
            matching: "Meeting searches include body/date, approved topic names, official document/transcript text, substantive agenda plans, and preferred resident analysis. Topic searches include names/aliases/descriptions, headlines, and resident briefing/timeline text.",
            filters: "Combine meeting q with from/to, committee_id, status, updated_since, or sort. Topic q combines with lifecycle, updated_since, or sort.",
            follow_up: "Read a topic briefing, appearances, and decisions, or meeting details, agenda_items, documents, and transcript. Follow official source links to verify generated claims."
          }
        },
        sorting: { meetings: "date (default) or updated", topics: "activity (default) or updated",
          direction: "Newest first with an ID tiebreaker. updated_since defaults to updated sorting." },
        endpoints: ENDPOINTS.map { |path, description| { url: "#{@base_url}/api/v1#{path}", description: description } },
        pagination: { default_limit: 50, maximum_limit: 100, offset: "Nonnegative integer. Follow links.next until null.",
          consistency: "Live reads; collections may change between pages." },
        transcript_pagination: { default_limit: 20_000, maximum_limit: 50_000,
          offset: "Unicode character offset; follow links.next, which pins document_id and checksum.",
          consistency: "A replaced or changed transcript returns 409 on pinned continuation requests." },
        sources: { summaries: "AI-generated analysis; follow the evidence links.",
          transcripts: "Supplemental recording text, not official minutes.",
          citations: "Validated citations provide document IDs, source URLs, versions and whole_source/pdf_page locations. Recording references never invent pages or timestamps. Legacy or changed-source references have status=unresolved and null document/link/page fields; their original labels remain visible. Citation repairs appear in updated_since results." },
        rate_limit: { requests: 120, per: "minute per account, shared across all keys", retry_header: "Retry-After" },
        errors: { "401" => "Missing, invalid, expired, revoked, or ineligible key", "404" => "Content not found",
          "409" => "Transcript revision changed", "422" => "Invalid filters or pagination", "429" => "Request limit reached" },
        key_management: "Create and revoke named keys in /settings/api_keys using your signed-in browser.",
        admin_access: false, writes: false }
    end
  end
end
