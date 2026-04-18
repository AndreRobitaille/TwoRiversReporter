require "uri"

module Scrapers
  class ParseAgendaJob < ApplicationJob
    queue_as :default

    def self.parse_and_reconcile(meeting_id)
      meeting = Meeting.find(meeting_id)
      agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_html")
      agenda_pdf_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")
      new.send(:parse_and_reconcile, meeting, meeting_id: meeting_id, agenda_doc: agenda_doc, agenda_pdf_doc: agenda_pdf_doc)
    end

    SECTION_PATTERN = /(\d+\.)\s+(.+?)(?=\s+\d+\.\s+|\z)/m
    CHILD_PATTERN = /([a-z]\.)\s+(.+?)(?=\s+[a-z]\.\s+|\z)/im
    RECOMMENDED_ACTION_PATTERN = /\s+-\s+Action\s+Recommended\s+/i

    def self.meeting_has_usable_agenda_source?(meeting)
      meeting.meeting_documents.any? do |agenda_document|
        case agenda_document.document_type
        when "agenda_pdf"
          agenda_document.extracted_text.to_s.strip.present?
        when "agenda_html"
          agenda_document.file.attached?
        else
          false
        end
      end
    end

    def perform(meeting_id)
      meeting = Meeting.find(meeting_id)
      agenda_doc = meeting.meeting_documents.find_by(document_type: "agenda_html")
      agenda_pdf_doc = meeting.meeting_documents.find_by(document_type: "agenda_pdf")

      parse_and_reconcile(meeting, meeting_id:, agenda_doc:, agenda_pdf_doc:)
    end

    private

    def parse_and_reconcile(meeting, meeting_id: nil, agenda_doc: nil, agenda_pdf_doc: nil)
      meeting_id ||= meeting.id
      agenda_doc ||= meeting.meeting_documents.find_by(document_type: "agenda_html")
      agenda_pdf_doc ||= meeting.meeting_documents.find_by(document_type: "agenda_pdf")
      candidates = build_candidates(meeting_id:, agenda_doc:, agenda_pdf_doc:)
      return :noop if candidates.blank?

      changed = reconcile_candidates(meeting, candidates)
      return :noop unless changed

      attach_candidate_links(meeting, candidates)
      Rails.logger.info "Parsed agenda items for Meeting #{meeting_id}"
      ExtractTopicsJob.perform_later(meeting_id)
      :changed
    rescue ActiveStorage::FileNotFoundError
      return fallback_to_pdf_agenda(meeting, meeting_id:, agenda_pdf_doc:) if agenda_pdf_doc&.extracted_text.present?

      raise
    end

    def build_candidates(meeting_id:, agenda_doc:, agenda_pdf_doc:)
      if agenda_doc&.file&.attached?
        candidates = parse_html_agenda(agenda_doc)
        return candidates if candidates.present?

        if agenda_pdf_doc&.extracted_text.to_s.strip.present?
          Rails.logger.info "Agenda HTML yielded no candidates for Meeting #{meeting_id}; falling back to agenda_pdf extracted text"
          return parse_pdf_agenda_text(agenda_pdf_doc.extracted_text)
        end

        candidates
      elsif agenda_pdf_doc&.extracted_text.present?
        parse_pdf_agenda_text(agenda_pdf_doc.extracted_text)
      else
        Rails.logger.info "No parseable agenda document found for Meeting #{meeting_id}"
        nil
      end
    end

    def fallback_to_pdf_agenda(meeting, meeting_id:, agenda_pdf_doc:)
      candidates = parse_pdf_agenda_text(agenda_pdf_doc.extracted_text)
      return :noop if candidates.blank?

      changed = reconcile_candidates(meeting, candidates)
      return :noop unless changed

      attach_candidate_links(meeting, candidates)
      Rails.logger.warn "Agenda HTML attachment missing for Meeting #{meeting_id}; fell back to agenda_pdf extracted text"
      ExtractTopicsJob.perform_later(meeting_id)
      :changed
    end

    def reconcile_candidates(meeting, candidates)
      digest = Agendas::ReconcileItems.digest_for_candidates(candidates)
      if meeting.agenda_structure_digest == digest && meeting.agenda_items.exists?
        Rails.logger.info "Agenda structure unchanged for Meeting #{meeting.id}"
        return false
      end

      result = nil
      meeting.with_lock do
        meeting.reload

        if meeting.agenda_structure_digest == digest && meeting.agenda_items.exists?
          Rails.logger.info "Agenda structure unchanged for Meeting #{meeting.id}"
          result = Agendas::ReconcileItems::Result.new(noop?: true)
          next
        end

        ActiveRecord::Base.transaction do
          result = Agendas::ReconcileItems.new(meeting: meeting, candidates: candidates).call
        end
      end

      !result.noop?
    rescue Agendas::ReconcileItems::AmbiguousMatchError
      Rails.logger.warn "Ambiguous agenda upgrade for Meeting #{meeting.id}; preserving existing agenda state"
      raise
    end

    def parse_html_agenda(agenda_doc)
      content = agenda_doc.file.download
      doc = Nokogiri::HTML(content)
      base_url = agenda_doc.source_url
      current_index = 0
      candidates = []

      doc.css("section.agenda-section").each do |section|
        header = section.at("h2.section-header")
        next unless header

        number = header.at("num")&.text&.strip
        title_span = header.at("span[style*='font-weight:bold']") || header.at("span")
        title = title_span&.text&.strip

        next if title.blank?

        li_nodes = section.css("ol.agenda-items > li")
        parent_candidate = {
          number: number,
          title: title,
          kind: li_nodes.any? ? "section" : "item",
          parent_key: nil,
          order_index: current_index += 1,
          summary: nil,
          recommended_action: nil,
          linked_documents: []
        }
        candidates << parent_candidate

        li_nodes.each do |li|
          div = li.at("div[class^='Section']")
          next unless div

          first_p = div.at("p")
          next unless first_p

          title_parts = []
          first_p.children.each do |child|
            next if child.name == "num"
            title_parts << child.text
          end

          candidates << {
            number: div.at("num")&.text&.strip,
            title: title_parts.join(" ").strip.squish,
            kind: "item",
            parent_key: candidate_key(parent_candidate),
            summary: extract_summary(div),
            recommended_action: extract_recommended_action(div),
            order_index: current_index += 1,
            linked_documents: div.css("a").map { |link| link["href"] }.compact,
            base_url: base_url
          }
        end
      end

      candidates
    end

    def parse_pdf_agenda_text(text)
      current_index = 0
      candidates = []

      text.to_s.scan(SECTION_PATTERN).each do |number, body|
        body = body.to_s.squish
        child_matches = body.to_enum(:scan, CHILD_PATTERN).map { Regexp.last_match }

        title = if child_matches.any?
          body[0...child_matches.first.begin(0)].to_s.squish
        else
          body
        end

        next if title.blank?

        parent_candidate = {
          number: number,
          title: title,
          kind: child_matches.any? ? "section" : "item",
          parent_key: nil,
          order_index: current_index += 1,
          summary: nil,
          recommended_action: nil,
          linked_documents: []
        }
        candidates << parent_candidate

        child_matches.each do |match|
          sub_number = match[1]
          child_text = match[2].to_s.squish
          next if child_text.blank?

          sub_title, recommended_action = split_inline_recommended_action(child_text)
          next if sub_title.blank?

          candidates << {
            number: sub_number,
            title: sub_title,
            kind: "item",
            parent_key: candidate_key(parent_candidate),
            recommended_action: recommended_action,
            order_index: current_index += 1,
            summary: nil,
            linked_documents: []
          }
        end
      end

      candidates
    end

    def attach_candidate_links(meeting, candidates)
      candidates.each do |candidate|
        next if candidate[:linked_documents].blank?

        agenda_item = meeting.agenda_items.find_by(candidate_lookup(meeting, candidate))
        next unless agenda_item

        candidate[:linked_documents].each do |href|
          next if href.blank?

          begin
            full_url = URI.join(candidate[:base_url], href).to_s
          rescue URI::InvalidURIError
            Rails.logger.warn "Invalid URI found in agenda: #{href}"
            next
          end

          doc = meeting.meeting_documents.find_or_create_by!(source_url: full_url) do |meeting_document|
            meeting_document.document_type = "attachment_pdf"
            meeting_document.fetched_at = nil
          end

          AgendaItemDocument.find_or_create_by!(agenda_item: agenda_item, meeting_document: doc)
          Documents::DownloadJob.perform_later(doc.id) if doc.fetched_at.nil? && defined?(Documents::DownloadJob)
        end
      end
    end

    def candidate_lookup(meeting, candidate)
      lookup = {
        number: candidate[:number],
        title: candidate[:title],
        kind: candidate[:kind]
      }

      parent_id = parent_id_for_candidate(meeting, candidate[:parent_key])
      lookup[:parent_id] = parent_id
      lookup
    end

    def parent_id_for_candidate(meeting, parent_key)
      return nil if parent_key.blank?

      meeting.agenda_items.find_by(candidate_lookup(meeting, parent_key))&.id
    end

    def candidate_key(candidate)
      {
        number: candidate[:number],
        title: candidate[:title],
        kind: candidate[:kind],
        parent_key: candidate[:parent_key]
      }
    end

    def extract_summary(div)
      tagged_paragraph_text(div, "Summary:")
    end

    def extract_recommended_action(div)
      tagged_paragraph_text(div, "Recommended Action:")
    end

    def tagged_paragraph_text(div, label)
      paragraph = div.css("p").find { |p_tag| p_tag.text.strip.start_with?(label) }
      return nil unless paragraph

      paragraph.text.sub(/^#{Regexp.escape(label)}\s*/i, "").strip
    end

    def split_inline_recommended_action(text)
      title, recommended_action = text.split(RECOMMENDED_ACTION_PATTERN, 2)
      [ title.to_s.strip, recommended_action&.strip ]
    end
  end
end
