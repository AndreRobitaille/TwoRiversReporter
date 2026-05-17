module Scrapers
  class DiscoverMeetingsJob < ApplicationJob
    queue_as :default

    MEETINGS_URL = "https://www.two-rivers.org/meetings"

    DEFAULT_LOOKBACK = 90.days

    def self.run_inline!(since: nil, enqueue_transcripts: true, enqueue_parse_jobs: true)
      meeting_ids = new.discover_meeting_ids(since: since, enqueue_parse_jobs: enqueue_parse_jobs)
      Scrapers::DiscoverTranscriptsJob.perform_later if enqueue_transcripts
      meeting_ids
    end

    def perform(since: nil)
      self.class.run_inline!(since: since)
    end

    def discover_meeting_ids(since: nil, enqueue_parse_jobs: true)
      since ||= DEFAULT_LOOKBACK.ago
      agent = Mechanize.new
      agent.user_agent_alias = "Mac Safari"
      page = agent.get(MEETINGS_URL)

      meeting_ids = []

      loop do
        should_continue, ids = parse_page(page, since, enqueue_parse_jobs: enqueue_parse_jobs)
        meeting_ids.concat(Array(ids))
        break unless should_continue

        next_link = page.link_with(text: /next ›/)
        break unless next_link

        page = next_link.click
      end

      meeting_ids
    end

    private

    def parse_page(page, since, enqueue_parse_jobs: true)
      rows = page.search("table.views-table tbody tr")
      meeting_ids = []

      rows.each do |row|
        result = process_row(row, since, enqueue_parse_jobs: enqueue_parse_jobs)
        if result == :stop
          return [ false, meeting_ids ]
        end

        meeting_ids << result if result.is_a?(Integer)
      end

      [ true, meeting_ids ]
    end

    def process_row(row, since, enqueue_parse_jobs: true)
      # Extract Data
      date_span = row.at(".views-field-field-calendar-date span")
      return unless date_span

      starts_at = Time.zone.parse(date_span["content"]) rescue nil
      return unless starts_at # Skip if we can't parse date

      # Check cutoff
      if since && starts_at < since
        Rails.logger.info "Reached cutoff date #{since} (found #{starts_at}). Stopping."
        return :stop
      end

      # Title column contains the Body Name (e.g. "City Council Meeting")
      # We might want to clean this up later (remove "Meeting"), but for now keep it raw
      title_text = row.at(".views-field-title").text.strip

      # View Details Link
      details_link = row.at(".views-field-view-node a")
      return unless details_link

      detail_url = details_link["href"]
      # Ensure absolute URL
      detail_url = "https://www.two-rivers.org#{detail_url}" unless detail_url.start_with?("http")

      # Upsert Meeting
      meeting = find_existing_meeting(starts_at, title_text, detail_url)
      preserve_existing_details = preserve_existing_details?(meeting, title_text)

      # Update attributes
      meeting.detail_page_url = detail_url unless preserve_existing_details
      meeting.starts_at = starts_at
      meeting.body_name = title_text unless preserve_existing_details
      meeting.committee = Committee.resolve(title_text) unless preserve_existing_details
      meeting.meeting_type = "regular" # Default, can be refined later
      meeting.status = determine_status(starts_at)

      if meeting.committee_id.blank? && meeting.body_name.present?
        Rails.logger.warn "DiscoverMeetingsJob: No committee match for body_name='#{meeting.body_name}'"
      end

      if meeting.save
        Scrapers::ParseMeetingPageJob.perform_later(meeting.id) if enqueue_parse_jobs
        meeting.id
      else
        Rails.logger.error("DiscoverMeetingsJob: Failed to save meeting (#{detail_url}): #{meeting.errors.full_messages.join(', ')}")
      end
    end

    def determine_status(starts_at)
      return "upcoming" if starts_at > Time.current
      "held"
    end

    def find_existing_meeting(starts_at, title_text, detail_url)
      Meeting.find_by(detail_page_url: detail_url) ||
        Meeting.where(starts_at: starts_at).find do |meeting|
          Meeting.normalized_body_name(meeting.body_name) == Meeting.normalized_body_name(title_text)
        end ||
        Meeting.new(detail_page_url: detail_url)
    end

    def preserve_existing_details?(meeting, title_text)
      meeting.persisted? && cancelled_title?(title_text) && !cancelled_title?(meeting.body_name)
    end

    def cancelled_title?(title_text)
      title_text.to_s.match?(/\b(cancelled|canceled)\b/i)
    end
  end
end
