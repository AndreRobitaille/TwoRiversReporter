module Scrapers
  class DiscoverMeetingsJob < ApplicationJob
    queue_as :default

    MEETINGS_URL = "https://www.two-rivers.org/meetings"

    def perform(since: nil)
      agent = Mechanize.new
      agent.user_agent_alias = "Mac Safari"
      page = agent.get(MEETINGS_URL)

      loop do
        should_continue = parse_page(page, since)
        break unless should_continue

        next_link = page.link_with(text: /next ›/)
        break unless next_link

        page = next_link.click
      end
    end

    private

    def parse_page(page, since)
      rows = page.search("table.views-table tbody tr")

      rows.each do |row|
        result = process_row(row, since)
        return false if result == :stop
      end

      true
    end

    def process_row(row, since)
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
      meeting = Meeting.find_or_initialize_by(detail_page_url: detail_url)

      # Update attributes
      meeting.starts_at = starts_at
      meeting.body_name = title_text
      meeting.meeting_type = "regular" # Default, can be refined later
      meeting.status = determine_status(starts_at)

      if meeting.save
        # Enqueue parsing of the detail page
        Scrapers::ParseMeetingPageJob.perform_later(meeting.id)
      end

      :continue
    end

    def determine_status(starts_at)
      return "upcoming" if starts_at > Time.current
      "held"
    end
  end
end
