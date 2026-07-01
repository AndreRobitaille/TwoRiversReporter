require "test_helper"

class GeneratedImages::GenerateForTopicJobTest < ActiveJob::TestCase
  setup do
    @topic = Topic.create!(name: "Eligible Topic", status: "approved", reuse_strategy: "canonical", resident_impact_score: 5, last_activity_at: 1.day.ago)
    @briefing = TopicBriefing.create!(topic: @topic, headline: "Headline", upcoming_headline: "Next up", editorial_content: "Editorial", record_content: "Record", generation_tier: "full")
  end

  test "returns when disabled" do
    logged = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| logged << message }

    Rails.stub :logger, logger do
      GeneratedImages::Config.stub :enabled?, false do
        GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
      end
    end

    assert_match(/GenerateForTopicJob skipped: config disabled/i, logged.first)
  end

  test "logs ineligible topic skip reason" do
    @topic.update!(resident_impact_score: 3)
    logged = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| logged << message }

    Rails.stub :logger, logger do
      GeneratedImages::Config.stub :enabled?, true do
        GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
      end
    end

    assert_match(/not in homepage top six/i, logged.first)
  end

  test "force generates when disabled" do
    captured = nil

    GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
      captured = { imageable: imageable, source: source, eligibility: eligibility, custom_prompt: custom_prompt, generated_image: generated_image }
      Object.new.tap { |o| o.define_singleton_method(:call) { true } }
    end do
      GeneratedImages::Config.stub :enabled?, false do
        GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
      end
    end

    assert_equal @topic, captured[:imageable]
    assert_equal @briefing, captured[:source]
    assert_predicate captured[:eligibility], :eligible?
    assert_predicate captured[:generated_image], :admin_override
  end

  test "generates when eligible and stale" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    generator_obj = Object.new
    generator_obj.define_singleton_method(:call) { true }
    captured = nil

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = { imageable: imageable, source: source, eligibility: eligibility, custom_prompt: custom_prompt }
        generator_obj
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, custom_prompt: "Warmer")
        end
      end
    end

    assert_equal @topic, captured[:imageable]
    assert_equal @briefing, captured[:source]
    assert_equal true, captured[:eligibility].eligible?
    assert_nil captured[:eligibility].reason
    assert_equal "Warmer", captured[:custom_prompt]
    assert true
  end

  test "skips when fingerprint already matches ready image" do
    GeneratedImages::Config.stub :enabled?, true do
      eligibility_obj = Object.new
      eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
      image = @topic.generated_images.create!(status: "ready", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), generated_at: Time.current)
      assert_predicate image, :ready?
      GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
      end
    end

    assert_equal 1, @topic.generated_images.count
  end

  test "automatic generation skips when a ready admin upload exists" do
    @topic.generated_images.create!(
      status: "ready",
      purpose: "feature_and_og",
      admin_override: true,
      source_generation_tier: "admin_upload",
      generated_at: Time.current
    )

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate over admin upload" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal 1, @topic.generated_images.count
    assert_equal 1, @topic.generated_images.ready.where(admin_override: true, source_generation_tier: "admin_upload").count
  end

  test "skips when matching processing image already exists" do
    @topic.generated_images.create!(status: "processing", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing))

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert true
  end

  test "fresh processing row blocks even if stale row exists" do
    fingerprint = GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing)
    @topic.generated_images.create!(status: "processing", purpose: "feature_and_og", source_content_fingerprint: fingerprint, updated_at: 2.hours.ago)
    @topic.generated_images.create!(status: "processing", purpose: "feature_and_og", source_content_fingerprint: fingerprint, updated_at: 5.minutes.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal 2, @topic.generated_images.where(status: "processing").count
  end

  test "retrying after failed image passes retrying_after to generator" do
    failed = @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), retry_count: 1)
    captured = nil

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = retrying_after
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal failed, captured
  end

  test "exhausted failed image skips automatic generation" do
    @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), retry_count: 2)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal 1, @topic.generated_images.where(status: "failed").count
  end

  test "third automatic run skips after first failure and one retry" do
    fingerprint = GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing)
    @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: fingerprint, retry_count: 1)
    @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: fingerprint, retry_count: 2)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal 2, @topic.generated_images.where(status: "failed").count
  end

  test "custom prompt bypasses exhausted failure" do
    @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), retry_count: 2)
    captured = nil

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = custom_prompt
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, custom_prompt: "Custom art direction")
        end
      end
    end

    assert_equal "Custom art direction", captured
  end

  test "custom prompt still skips when fresh processing exists" do
    @topic.generated_images.create!(status: "processing", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), updated_at: 5.minutes.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, custom_prompt: "Custom art direction")
        end
      end
    end

    assert_equal 1, @topic.generated_images.where(status: "processing").count
  end

  test "transient failure marks reservation failed so next run retries generation" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
    fingerprint = GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing)
    @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: fingerprint, retry_count: 1, failure_reason: "timeout")
    calls = 0

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::Generator.stub :new, ->(*) do
          calls += 1
          Object.new.tap { |o| o.define_singleton_method(:call) { true } }
        end do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal 1, calls
  end

  test "force bypasses exhausted failure" do
    @topic.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), retry_count: 2)
    captured = nil

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = { custom_prompt: custom_prompt, retrying_after: retrying_after }
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
        end
      end
    end

    assert_nil captured[:retrying_after]
  end

  test "force with blank custom prompt marks reservation as admin override" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
    captured = nil

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = generated_image
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
        end
      end
    end

    assert_predicate captured, :admin_override
    assert_nil captured.custom_prompt
  end

  test "force still generates when a ready admin upload exists" do
    @topic.generated_images.create!(
      status: "ready",
      purpose: "feature_and_og",
      admin_override: true,
      source_generation_tier: "admin_upload",
      generated_at: Time.current
    )
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
    captured = nil

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = generated_image
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
        end
      end
    end

    assert_predicate captured, :admin_override
    assert_equal 2, @topic.generated_images.count
  end

  test "force bypasses topic eligibility checks" do
    eligibility_called = false
    captured = nil

    GeneratedImages::TopicEligibility.stub :new, ->(*) do
      eligibility_called = true
      raise "should not call auto eligibility when forced"
    end do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = eligibility
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
        end
      end
    end

    assert_equal false, eligibility_called
    assert_predicate captured, :eligible?
    assert_equal false, captured.composite?
  end

  test "force still skips when fresh processing exists" do
    @topic.generated_images.create!(status: "processing", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), updated_at: 5.minutes.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, force: true)
        end
      end
    end

    assert_equal 1, @topic.generated_images.where(status: "processing").count
  end

  test "expired processing image is failed and replaced" do
    old = @topic.generated_images.create!(status: "processing", purpose: "feature_and_og", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing), updated_at: 2.hours.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
    captured = nil

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) { captured = generated_image; Object.new.tap { |o| o.define_singleton_method(:call) { true } } } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal "failed", old.reload.status
    assert_equal "Processing reservation expired", old.failure_reason
    assert_not_nil captured
  end

  test "uses briefing source" do
    captured = nil
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }

    generator_obj = Object.new
    generator_obj.define_singleton_method(:call) { true }

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::Generator.stub :new, ->(imageable, source:, **kwargs) { captured = [ imageable, source, kwargs ]; generator_obj } do
          GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
        end
      end
    end

    assert_equal @topic, captured[0]
    assert_equal @briefing, captured[1]
  end

  test "custom prompt forces generation even with matching fingerprint" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
    captured = nil

    GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
      @topic.stub :generated_images, @topic.generated_images.ready do
        GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
          captured = { imageable: imageable, source: source, eligibility: eligibility, custom_prompt: custom_prompt }
          Object.new.tap { |o| o.define_singleton_method(:call) { true } }
        end do
          GeneratedImages::Config.stub :enabled?, true do
            GeneratedImages::GenerateForTopicJob.perform_now(@topic.id, custom_prompt: "Custom art direction")
          end
        end
      end
    end

    assert_equal "Custom art direction", captured[:custom_prompt]
  end

  test "generic failed generation enqueues one retry" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason).new(true, nil) }
    fingerprint = GeneratedImages::ContentFingerprint.for_topic_briefing(@briefing)
    first_result = nil
    call_count = 0

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::TopicEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
          call_count += 1
          if call_count == 1
            first_result = imageable.generated_images.create!(status: "failed", purpose: "feature_and_og", source_content_fingerprint: fingerprint, retry_count: 1, failure_reason: "generic failure")
            Object.new.tap { |o| o.define_singleton_method(:call) { first_result } }
          else
            Object.new.tap { |o| o.define_singleton_method(:call) { true } }
          end
        end do
          assert_enqueued_with(job: GeneratedImages::GenerateForTopicJob, args: [ @topic.id, { custom_prompt: nil, force: false } ]) do
            GeneratedImages::GenerateForTopicJob.perform_now(@topic.id)
          end
        end
      end
    end

    assert_equal 1, call_count
    assert_equal 1, @topic.generated_images.where(status: "failed").maximum(:retry_count)
  end
end
