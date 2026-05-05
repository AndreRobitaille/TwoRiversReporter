require "uri"

module Scrapers
  class ParseMeetingPageJob < ApplicationJob
    queue_as :default

    def perform(meeting_id, enqueue_downloads: true)
      meeting = Meeting.find(meeting_id)
      parsed_successfully = false

      agent = Mechanize.new
      agent.user_agent_alias = "Mac Safari"
      begin
        page = agent.get(meeting.detail_page_url)
      rescue Mechanize::ResponseCodeError => e
        Rails.logger.error "Failed to fetch meeting page #{meeting.detail_page_url}: #{e.message}"
        return
      rescue StandardError => e
        Rails.logger.error "Error parsing meeting page #{meeting.detail_page_url}: #{e.message}"
        return
      end

      # Extract Documents
      extract_documents(meeting, page, enqueue_downloads: enqueue_downloads)
      parsed_successfully = true
    ensure
      meeting.mark_processing!(:meeting_page_parsed_at) if parsed_successfully
    end

    private

    def extract_documents(meeting, page, enqueue_downloads: true)
      # The structure is usually inside .related_info.meeting_info
      container = page.at(".related_info.meeting_info")

      unless container
        Rails.logger.warn "No .related_info.meeting_info found for meeting #{meeting.id}"
        return
      end

      # Map CSS classes to generic types
      type_mappings = {
        ".agendas" => "agenda",
        ".packets" => "packet",
        ".minutes" => "minutes"
      }

      type_mappings.each do |css_class, base_type|
        section = container.at(css_class)
        next unless section

        # Find all links in this section
        section.search("a").each do |link|
          href = link["href"]
          next if href.blank?

          source_url = normalize_source_url(meeting.detail_page_url, href)

          # Determine specific type (pdf vs html)
          doc_type = determine_doc_type(base_type, href)

          # Create MeetingDocument
          doc = meeting.meeting_documents.find_or_initialize_by(source_url: source_url)
          doc.document_type = doc_type

          if doc.new_record? || doc.changed?
            doc.save!
            Rails.logger.info "Found document: #{doc_type} at #{source_url}"
          end

          # Always enqueue download to check for remote content updates
          # The DownloadJob will handle conditional GETs to avoid unnecessary work
          Documents::DownloadJob.perform_later(doc.id) if enqueue_downloads
        end
      end
    end

    def determine_doc_type(base, url)
      if url.downcase.include?(".pdf")
        "#{base}_pdf"
      else
        "#{base}_html"
      end
    end

    def normalize_source_url(base_url, href)
      URI.join(base_url, href).to_s
    rescue URI::InvalidURIError
      href
    end
  end
end
