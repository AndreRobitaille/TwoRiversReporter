require "uri"

module Scrapers
  class ParseAgendaJob < ApplicationJob
    queue_as :default

    def perform(meeting_id)
      meeting = Meeting.find(meeting_id)
      agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_html")

      unless agenda_doc&.file&.attached?
        Rails.logger.info "No agenda_html document found for Meeting #{meeting_id}"
        return
      end

      # Clear existing items to avoid duplicates on re-run
      meeting.agenda_items.destroy_all

      content = agenda_doc.file.download
      doc = Nokogiri::HTML(content)
      base_url = agenda_doc.source_url

      current_index = 0

      # 1. Top-level sections (e.g. "1. CALL TO ORDER")
      doc.css("section.agenda-section").each do |section|
        header = section.at("h2.section-header")
        next unless header

        number = header.at("num")&.text&.strip
        # Title is usually the first bold span
        title_span = header.at("span[style*='font-weight:bold']") || header.at("span")
        title = title_span&.text&.strip

        next if title.blank?

        # Save Top Level Item
        meeting.agenda_items.create!(
          number: number,
          title: title,
          summary: nil,
          recommended_action: nil,
          order_index: current_index += 1
        )

        # 2. Sub-items (nested in ol.agenda-items) within this section
        section.css("ol.agenda-items > li").each do |li|
          div = li.at("div[class^='Section']")
          next unless div

          sub_number = div.at("num")&.text&.strip

          # Title extraction (first p, excluding num)
          first_p = div.at("p")
          next unless first_p

          title_parts = []
          first_p.children.each do |child|
            next if child.name == "num"
            title_parts << child.text
          end
          sub_title = title_parts.join(" ").strip.squish

          # Extract Summary and Recommended Action
          summary = nil
          recommended_action = nil

          div.css("p").each do |p_tag|
            text = p_tag.text.strip
            if text.start_with?("Summary:")
              summary = text.sub(/^Summary:\s*/i, "").strip
            elsif text.start_with?("Recommended Action:")
              recommended_action = p_tag.text.sub(/^Recommended Action:\s*/i, "").strip
            end
          end

          agenda_item = meeting.agenda_items.create!(
            number: sub_number,
            title: sub_title,
            summary: summary,
            recommended_action: recommended_action,
            order_index: current_index += 1
          )

          # Extract and Link Attachments
          div.css("a").each do |link|
            href = link["href"]
            next if href.blank?

            # Resolve full URL relative to agenda_doc source
            begin
              full_url = URI.join(base_url, href).to_s
            rescue URI::InvalidURIError
              Rails.logger.warn "Invalid URI found in agenda: #{href}"
              next
            end

            # Find or Create Document (mark fetched_at: nil to trigger download later if new)
            doc = meeting.meeting_documents.find_or_create_by!(source_url: full_url) do |d|
              d.document_type = "attachment_pdf"
              d.fetched_at = nil
            end

            AgendaItemDocument.create!(agenda_item: agenda_item, meeting_document: doc)

            # Trigger download if it's a new document (fetched_at is nil)
            # Note: We don't have a DownloadJob trigger here yet, but ideally we should.
            # Assuming an external process or scheduled job picks up nil fetched_at docs.
            # Or we can trigger it if DownloadJob exists.
            Documents::DownloadJob.perform_later(doc.id) if doc.fetched_at.nil? && defined?(Documents::DownloadJob)
          end
        end
      end

      Rails.logger.info "Parsed agenda items for Meeting #{meeting_id}"
      ExtractTopicsJob.perform_later(meeting_id)
    end
  end
end
