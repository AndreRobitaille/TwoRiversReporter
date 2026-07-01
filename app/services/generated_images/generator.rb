module GeneratedImages
  class Generator
    DEFAULT_PURPOSE = "feature_and_og"
    DEFAULT_SIZE = "1536x1024"
    DEFAULT_OUTPUT_FORMAT = "jpeg"

    def initialize(imageable, source:, purpose: DEFAULT_PURPOSE, custom_prompt: nil, eligibility: nil, generated_image: nil, retrying_after: nil, ai_service: Ai::OpenAiService.new)
      @imageable = imageable
      @source = source
      @purpose = purpose
      @custom_prompt = custom_prompt
      @eligibility = eligibility
      @image = generated_image
      @retrying_after = retrying_after
      @ai_service = ai_service
    end

    def call
      image = @image || @imageable.generated_images.create!(
        status: "pending",
        purpose: @purpose,
        custom_prompt: @custom_prompt,
        admin_override: @custom_prompt.present?,
        source_summary: source_summary,
        source_briefing: source_briefing,
        source_generation_tier: source_generation_tier,
        source_content_fingerprint: source_content_fingerprint,
        requested_size: DEFAULT_SIZE,
        output_format: DEFAULT_OUTPUT_FORMAT
      )

      image.update!(status: "processing")
      eligibility_result = eligibility_result_for
      visual_brief = VisualBriefBuilder.new(@imageable, source: @source, eligibility: eligibility_result, ai_service: @ai_service).call
      prompt = build_prompt(visual_brief)
      image.update!(visual_brief: visual_brief, prompt: prompt)
      result = @ai_service.generate_civic_image(prompt: prompt, size: DEFAULT_SIZE, output_format: DEFAULT_OUTPUT_FORMAT)

      @imageable.generated_images.transaction do
        @imageable.lock!
        if automatic_generation?(image) && ready_admin_override_exists?(except: image)
          image.update!(status: "superseded", failure_reason: "Admin override exists")
        else
          image.file.attach(io: StringIO.new(result[:bytes]), filename: filename_for(result[:format]), content_type: content_type_for(result[:format]))
          supersede_previous_ready_images(except: image)
          image.update!(
            status: "ready",
            generated_at: Time.current,
            model: result[:model],
            output_format: result[:format],
            requested_size: result[:size],
            failure_reason: nil,
            retry_count: image.retry_count
          )
        end
      end
      image
    rescue Faraday::Error, Net::OpenTimeout, Net::ReadTimeout => e
      image&.update!(status: "failed", retry_count: image.retry_count + 1, failure_reason: e.message) if image
      raise
    rescue ActiveRecord::RecordInvalid, ActiveModel::ValidationError, ActiveRecord::RecordNotSaved, ActiveRecord::RecordNotDestroyed => e
      raise
    rescue StandardError => e
      image&.file&.purge if image&.file&.attached? && !image.ready?
      image&.update!(status: "failed", retry_count: image.retry_count + 1, failure_reason: e.message) if image
      image
    end

    private

    def eligibility
      case @source
      when MeetingSummary then GeneratedImages::MeetingEligibility.new(@imageable, summary: @source)
      when TopicBriefing then GeneratedImages::TopicEligibility.new(@imageable)
      end
    end

    def eligibility_result_for
      return @eligibility if @eligibility

      eligibility = self.send(:eligibility)
      eligibility&.call
    end

    def source_summary
      @source if @source.is_a?(MeetingSummary)
    end

    def source_briefing
      @source if @source.is_a?(TopicBriefing)
    end

    def source_generation_tier
      case @source
      when MeetingSummary then @source.summary_type
      when TopicBriefing then @source.generation_tier
      end
    end

    def source_content_fingerprint
      case @source
      when MeetingSummary then GeneratedImages::ContentFingerprint.for_meeting_summary(@source)
      when TopicBriefing then GeneratedImages::ContentFingerprint.for_topic_briefing(@source)
      end
    end

    def build_prompt(brief)
      base = [
        "Create a realistic local newspaper editorial photograph for #{brief["civic_issue"] || @imageable.class.name}.",
        "Focus on one dominant resident-visible physical anchor.",
        brief["composition"],
        "Avoid: #{Array(brief["avoid"]).join(', ')}.",
        "Guardrails: no collage, no fake readable document text, no invented people, no invented local landmarks, no logos, no charts, no headline typography, avoid coins, gavels, and paper clichés."
      ].compact.join(" ")
      base = [ base, retrying_after_instruction ].compact.join(" ")
      @custom_prompt.present? ? [ base, @custom_prompt ].join(" ") : base
    end

    def retrying_after_instruction
      return unless @retrying_after

      "Use a simpler, safer composition with one visible anchor, fewer elements, and no ambiguous people, text, or local landmarks."
    end

    def supersede_previous_ready_images(except:)
      @imageable.generated_images.ready.where.not(id: except.id).find_each do |existing|
        existing.update!(status: "superseded")
      end
    end

    def automatic_generation?(image)
      !image.admin_override?
    end

    def ready_admin_override_exists?(except:)
      @imageable.generated_images.ready.where(admin_override: true).where.not(id: except.id).exists?
    end

    def filename_for(format)
      "generated-image.#{format || DEFAULT_OUTPUT_FORMAT}"
    end

    def content_type_for(format)
      "image/#{format || DEFAULT_OUTPUT_FORMAT}"
    end
  end
end
