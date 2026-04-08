class ExtractVotesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      return
    end

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_votes(minutes_doc.extracted_text, source: meeting)

    begin
      data = JSON.parse(json_response)
      motions = data["motions"] || []

      ActiveRecord::Base.transaction do
        # Clear existing inside transaction to be idempotent
        meeting.motions.destroy_all

        motions.each do |m_data|
          motion = meeting.motions.create!(
            description: m_data["description"],
            outcome: m_data["outcome"]
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
end
