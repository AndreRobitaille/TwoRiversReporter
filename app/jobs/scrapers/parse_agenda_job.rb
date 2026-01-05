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

      items = []
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
        items << {
          meeting_id: meeting.id,
          number: number,
          title: title,
          summary: nil,
          recommended_action: nil,
          order_index: current_index += 1
        }

        # 2. Sub-items (nested in ol.agenda-items) within this section
        section.css("ol.agenda-items > li").each do |li|
          div = li.at("div[class^='Section']")
          next unless div

          sub_number = div.at("num")&.text&.strip

          # Title is often followed by the number, usually underlined or bold
          # Or sometimes just the first text node or span
          # In the sample: <span ... text-decoration: underline;">26-001</span><span ...> Public hearing...</span>
          # We might need to grab all text from the first paragraph that isn't Summary/Action

          # Let's look for the first paragraph
          first_p = div.at("p")
          next unless first_p

          # Extract title: Get text from first p, excluding the num tag
          # Use node traversal to be safer
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
              # Sometimes Recommended Action is in the following node, but usually in the p tag or br separated
              # In sample: <span ...>Recommended Action:</span><br><span ...>Motion to ...</span>
              # The text extraction above should handle it if it's all in the p_tag
            end
          end

          items << {
            meeting_id: meeting.id,
            number: sub_number,
            title: sub_title,
            summary: summary,
            recommended_action: recommended_action,
            order_index: current_index += 1
          }
        end
      end

      if items.any?
        # Add timestamps for insert_all
        now = Time.current
        items.each do |item|
          item[:created_at] = now
          item[:updated_at] = now
        end

        AgendaItem.insert_all(items)
        Rails.logger.info "Parsed #{items.size} agenda items for Meeting #{meeting_id}"
      else
        Rails.logger.warn "No agenda items parsed for Meeting #{meeting_id} (Format might be legacy)"
      end
    end
  end
end
