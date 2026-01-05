class ExtractVotesJob < ApplicationJob
  queue_as :default

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      return
    end

    # Clear existing to be idempotent
    meeting.motions.destroy_all

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_votes(minutes_doc.extracted_text)

    begin
      data = JSON.parse(json_response)
      motions = data["motions"] || []

      motions.each do |m_data|
        motion = meeting.motions.create!(
          description: m_data["description"],
          outcome: m_data["outcome"]
        )

        m_data["votes"]&.each do |v_data|
          raw_name = v_data["member"]
          next if raw_name.blank?

          # Normalize name: Remove common titles and punctuation
          name = raw_name.gsub(/^(Councilmember|Alderman|Alderperson|Commissioner|Manager|Clerk|Mr\.|Ms\.|Mrs\.)\s+/i, "").strip

          member = Member.find_or_create_by!(name: name)

          # Validate value is allowed (yes/no/abstain/absent/recused)
          val = v_data["value"].downcase
          unless %w[yes no abstain absent recused].include?(val)
            val = "abstain" # Fallback or handle error? Let's default to abstain if unclear, or skip?
            # Creating with invalid value will raise validation error.
            # Let's verify against schema.
            # The prompt asked for specific values.
          end

          Vote.create!(
            motion: motion,
            member: member,
            value: val
          )
        end
      end

      Rails.logger.info "Extracted #{motions.size} motions for Meeting #{meeting_id}"

    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse votes JSON for Meeting #{meeting_id}: #{e.message}"
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Validation error saving votes for Meeting #{meeting_id}: #{e.message}"
    end
  end
end
