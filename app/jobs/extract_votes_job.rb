class ExtractVotesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      return
    end

    agenda_items = meeting.agenda_items.order(:order_index).to_a
    agenda_items_text = build_agenda_items_text(agenda_items)

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_votes(
      minutes_doc.extracted_text,
      agenda_items_text: agenda_items_text,
      source: meeting
    )

    begin
      data = JSON.parse(json_response)
      motions = data["motions"] || []

      ActiveRecord::Base.transaction do
        meeting.motions.destroy_all

        motions.each do |m_data|
          agenda_item = resolve_agenda_item(m_data["agenda_item_ref"], agenda_items)

          motion = meeting.motions.create!(
            description: m_data["description"],
            outcome: m_data["outcome"],
            agenda_item: agenda_item
          )

          m_data["votes"]&.each do |v_data|
            raw_name = v_data["member"]
            next if raw_name.blank?

            member = Member.resolve(raw_name)
            next unless member

            val = v_data["value"]&.downcase
            next if val.blank?
            val = "abstain" unless %w[yes no abstain absent recused].include?(val)

            Vote.create!(
              motion: motion,
              member: member,
              value: val
            )
          end
        end
      end

      Rails.logger.info "Extracted #{motions.size} motions for Meeting #{meeting_id}"
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse votes JSON for Meeting #{meeting_id}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Validation error saving votes for Meeting #{meeting_id}: #{e.message}"
    end

    # Always trigger continuity update — even on partial failure, the meeting state changed
    Topics::UpdateContinuityJob.perform_later(meeting_id: meeting_id)
  end

  private

  def build_agenda_items_text(agenda_items)
    agenda_items.map { |item|
      item.number.present? ? "#{item.number}: #{item.title}" : item.title
    }.join("\n")
  end

  def resolve_agenda_item(ref, agenda_items)
    return nil if ref.blank?

    # Try matching by item number first
    number_match = ref.match(/\A(\S+?)(?:[\s:]|\z)/i)
    if number_match
      candidate = number_match[1]
      by_number = agenda_items.find { |item| item.number&.downcase == candidate.downcase }
      return by_number if by_number
    end

    # Fall back to title similarity (word overlap)
    ref_words = ref.downcase.gsub(/[^a-z0-9\s]/, "").split
    return nil if ref_words.empty?

    best_match = nil
    best_score = 0.0

    agenda_items.each do |item|
      next if item.title.blank?
      item_words = item.title.downcase.gsub(/[^a-z0-9\s]/, "").split
      next if item_words.empty?

      overlap = (ref_words & item_words).size
      score = overlap.to_f / [ ref_words.size, item_words.size ].max

      if score > best_score
        best_score = score
        best_match = item
      end
    end

    best_score >= 0.5 ? best_match : nil
  end
end
