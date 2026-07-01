module GeneratedImages
  class GenerateForMeetingJob < ApplicationJob
    queue_as :default
    PROCESSING_TIMEOUT = 30.minutes

    def perform(meeting_id, custom_prompt: nil, force: false)
      return log_skip("config disabled") unless GeneratedImages::Config.enabled?

      meeting = Meeting.find(meeting_id)
      payload = nil

      meeting.with_lock do
        summary = preferred_summary_for(meeting.reload)
        return log_skip("missing summary", meeting_id) unless summary

        eligibility = meeting_eligibility_for(meeting, summary, force: force, custom_prompt: custom_prompt)
        return log_skip("ineligible: #{eligibility.reason}", meeting_id) unless eligibility.eligible?

        fingerprint = GeneratedImages::ContentFingerprint.for_meeting_summary(summary)
        retrying_after = nil

        if custom_prompt.blank? && !force
          return log_skip("ready admin override", meeting_id) if meeting.generated_images.ready.where(admin_override: true).exists?
          return log_skip("ready duplicate", meeting_id) if meeting.generated_images.where(source_content_fingerprint: fingerprint, status: "ready").exists?

          if meeting.generated_images.where(source_content_fingerprint: fingerprint, status: "processing").where("updated_at >= ?", PROCESSING_TIMEOUT.ago).exists?
            return log_skip("fresh processing lock", meeting_id)
          end

          meeting.generated_images.where(source_content_fingerprint: fingerprint, status: "processing").where("updated_at < ?", PROCESSING_TIMEOUT.ago).find_each do |existing|
            existing.update!(status: "failed", failure_reason: "Processing reservation expired")
          end

          failed_images = meeting.generated_images.where(source_content_fingerprint: fingerprint, status: "failed").order(updated_at: :desc, created_at: :desc, id: :desc)
          case failed_images.count
          when 0
            retrying_after = nil
          when 1
            retrying_after = failed_images.first
            return log_skip("retry exhausted", meeting_id) unless retrying_after.retry_available?
          else
            return log_skip("retry exhausted", meeting_id)
          end
        end

        return log_skip("fresh processing lock", meeting_id) if meeting.generated_images.where(source_content_fingerprint: fingerprint, status: "processing").where("updated_at >= ?", PROCESSING_TIMEOUT.ago).exists?

        payload = {
          summary: summary,
          eligibility: eligibility,
          reservation: meeting.generated_images.create!(
            status: "processing",
            purpose: GeneratedImages::Generator::DEFAULT_PURPOSE,
            custom_prompt: custom_prompt,
            admin_override: custom_prompt.present? || force,
            source_summary: summary,
            source_generation_tier: summary.summary_type,
            source_content_fingerprint: fingerprint,
            requested_size: GeneratedImages::Generator::DEFAULT_SIZE,
            output_format: GeneratedImages::Generator::DEFAULT_OUTPUT_FORMAT,
            retry_count: retrying_after ? retrying_after.retry_count + 1 : 0
          ),
          retrying_after: retrying_after
        }
      end

      return unless payload

      result = GeneratedImages::Generator.new(
        meeting,
        source: payload[:summary],
        eligibility: payload[:eligibility],
        custom_prompt: custom_prompt,
        generated_image: payload[:reservation],
        retrying_after: payload[:retrying_after]
      ).call
      schedule_retry!(meeting.id, custom_prompt: custom_prompt, force: force) if retryable_failure?(result)
      result
    end

    private

    def preferred_summary_for(meeting)
      meeting.meeting_summaries
        .to_a
        .select { |summary| meeting_summary_usable?(summary) }
        .min_by { |summary| [ summary_priority(summary), -(summary.updated_at || summary.created_at || Time.at(0)).to_i ] }
    end

    def meeting_summary_usable?(summary)
      summary.content.present? || summary.generation_data.present?
    end

    def summary_priority(summary)
      %w[minutes_recap transcript_recap packet_analysis agenda_preview].index(summary.summary_type) || 99
    end

    def meeting_eligibility_for(meeting, summary, force:, custom_prompt:)
      return force_eligible_result if force || custom_prompt.present?

      GeneratedImages::MeetingEligibility.new(meeting, summary: summary).call
    end

    def force_eligible_result
      Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, nil, false)
    end

    def schedule_retry!(meeting_id, custom_prompt:, force:)
      GeneratedImages::GenerateForMeetingJob.perform_later(meeting_id, custom_prompt: custom_prompt, force: force)
    end

    def retryable_failure?(result)
      result.respond_to?(:failed?) && result.failed? && result.respond_to?(:retry_available?) && result.retry_available? && result.respond_to?(:retry_count) && result.retry_count == 1
    end

    def log_skip(reason, meeting_id = nil)
      Rails.logger.info("GeneratedImages::GenerateForMeetingJob skipped#{meeting_id ? " meeting=#{meeting_id}" : ""}: #{reason}")
      nil
    end
  end
end
