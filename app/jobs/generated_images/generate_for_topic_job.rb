module GeneratedImages
  class GenerateForTopicJob < ApplicationJob
    queue_as :default
    PROCESSING_TIMEOUT = 30.minutes

    def perform(topic_id, custom_prompt: nil, force: false)
      return unless GeneratedImages::Config.enabled?

      topic = Topic.find(topic_id)
      payload = nil

      topic.with_lock do
        briefing = topic.reload.topic_briefing
        return unless briefing

        eligibility = topic_eligibility_for(topic, force: force, custom_prompt: custom_prompt)
        return unless eligibility.eligible?

        fingerprint = GeneratedImages::ContentFingerprint.for_topic_briefing(briefing)
        retrying_after = nil

        if custom_prompt.blank? && !force
          return if topic.generated_images.where(source_content_fingerprint: fingerprint, status: "ready").exists?

          if topic.generated_images.where(source_content_fingerprint: fingerprint, status: "processing").where("updated_at >= ?", PROCESSING_TIMEOUT.ago).exists?
            return
          end

          topic.generated_images.where(source_content_fingerprint: fingerprint, status: "processing").where("updated_at < ?", PROCESSING_TIMEOUT.ago).find_each do |existing|
            existing.update!(status: "failed", failure_reason: "Processing reservation expired")
          end

          failed_images = topic.generated_images.where(source_content_fingerprint: fingerprint, status: "failed").order(updated_at: :desc, created_at: :desc, id: :desc)
          case failed_images.count
          when 0
            retrying_after = nil
          when 1
            retrying_after = failed_images.first
            return unless retrying_after.retry_available?
          else
            return
          end
        end

        return if topic.generated_images.where(source_content_fingerprint: fingerprint, status: "processing").where("updated_at >= ?", PROCESSING_TIMEOUT.ago).exists?

        payload = {
          briefing: briefing,
          eligibility: eligibility,
          reservation: topic.generated_images.create!(
            status: "processing",
            purpose: GeneratedImages::Generator::DEFAULT_PURPOSE,
            custom_prompt: custom_prompt,
            admin_override: custom_prompt.present? || force,
            source_briefing: briefing,
            source_generation_tier: briefing.generation_tier,
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
        topic,
        source: payload[:briefing],
        eligibility: payload[:eligibility],
        custom_prompt: custom_prompt,
        generated_image: payload[:reservation],
        retrying_after: payload[:retrying_after]
      ).call
      schedule_retry!(topic.id, custom_prompt: custom_prompt, force: force) if retryable_failure?(result)
      result
    end

    private

    def topic_eligibility_for(topic, force:, custom_prompt:)
      return force_eligible_result if force || custom_prompt.present?

      GeneratedImages::TopicEligibility.new(topic).call
    end

    def force_eligible_result
      Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, nil, false)
    end

    def schedule_retry!(topic_id, custom_prompt:, force:)
      GeneratedImages::GenerateForTopicJob.perform_later(topic_id, custom_prompt: custom_prompt, force: force)
    end

    def retryable_failure?(result)
      result.respond_to?(:failed?) && result.failed? && result.respond_to?(:retry_available?) && result.retry_available? && result.respond_to?(:retry_count) && result.retry_count == 1
    end
  end
end
