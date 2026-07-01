require "test_helper"

class GeneratedImages::GenerateForMeetingJobTest < ActiveJob::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago, detail_page_url: "http://example.com/meeting")
    @minutes = @meeting.meeting_summaries.create!(summary_type: "minutes_recap", content: "Minutes recap content", generation_data: { "headline" => "Council approved street repairs", "highlights" => [ { "text" => "Approved repairs" } ], "item_details" => [] })
    @packet = @meeting.meeting_summaries.create!(summary_type: "packet_analysis", content: "Packet analysis content", generation_data: { "headline" => "Packet analysis headline", "highlights" => [], "item_details" => [] })
  end

  test "returns when disabled" do
    logged = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| logged << message }

    Rails.stub :logger, logger do
      GeneratedImages::Config.stub :enabled?, false do
        GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
      end
    end

    assert_match(/GenerateForMeetingJob skipped: config disabled/i, logged.first)
  end

  test "logs ineligible meeting skip reason" do
    @meeting.meeting_summaries.delete_all
    logged = []
    logger = Object.new
    logger.define_singleton_method(:info) { |message| logged << message }

    Rails.stub :logger, logger do
      GeneratedImages::Config.stub :enabled?, true do
        GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
      end
    end

    assert_match(/missing summary/i, logged.first)
  end

  test "generates when eligible and fingerprint is stale" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) do
      Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false)
    end

    generator_obj = Object.new
    generator_obj.define_singleton_method(:call) { true }
    captured = nil

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = { imageable: imageable, source: source, eligibility: eligibility, custom_prompt: custom_prompt }
        generator_obj
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, custom_prompt: "Make it warmer")
        end
      end
    end

    assert_equal @meeting, captured[:imageable]
    assert_equal @minutes, captured[:source]
    assert_equal true, captured[:eligibility].eligible?
    assert_nil captured[:eligibility].reason
    assert_equal "Make it warmer", captured[:custom_prompt]
    assert true
  end

  test "skips when fingerprint already matches ready image" do
    GeneratedImages::Config.stub :enabled?, true do
      eligibility_obj = Object.new
      eligibility_obj.define_singleton_method(:call) do
        Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false)
      end
      image = @meeting.generated_images.create!(status: "ready", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes))
      assert_predicate image, :ready?
      GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
      end
    end

    assert_equal 1, @meeting.generated_images.count
  end

  test "automatic generation skips when a ready admin upload exists" do
    @meeting.generated_images.create!(
      status: "ready",
      admin_override: true,
      source_generation_tier: "admin_upload",
      generated_at: Time.current
    )

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) do
      Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false)
    end

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate over admin upload" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal 1, @meeting.generated_images.count
    assert_equal 1, @meeting.generated_images.ready.where(admin_override: true, source_generation_tier: "admin_upload").count
  end

  test "skips when matching processing image already exists" do
    @meeting.generated_images.create!(status: "processing", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes))

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) do
      Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false)
    end

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert true
  end

  test "fresh processing row blocks even if stale row exists" do
    fingerprint = GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes)
    @meeting.generated_images.create!(status: "processing", source_content_fingerprint: fingerprint, updated_at: 2.hours.ago)
    @meeting.generated_images.create!(status: "processing", source_content_fingerprint: fingerprint, updated_at: 5.minutes.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal 2, @meeting.generated_images.where(status: "processing").count
  end

  test "retrying after failed image passes retrying_after to generator" do
    failed = @meeting.generated_images.create!(status: "failed", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), retry_count: 1)
    captured = nil

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = retrying_after
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal failed, captured
  end

  test "exhausted failed image skips automatic generation" do
    @meeting.generated_images.create!(status: "failed", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), retry_count: 2)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal 1, @meeting.generated_images.where(status: "failed").count
  end

  test "third automatic run skips after first failure and one retry" do
    fingerprint = GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes)
    @meeting.generated_images.create!(status: "failed", source_content_fingerprint: fingerprint, retry_count: 1)
    @meeting.generated_images.create!(status: "failed", source_content_fingerprint: fingerprint, retry_count: 2)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal 2, @meeting.generated_images.where(status: "failed").count
  end

  test "custom prompt bypasses exhausted failure" do
    @meeting.generated_images.create!(status: "failed", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), retry_count: 2)
    captured = nil

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = custom_prompt
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, custom_prompt: "Custom art direction")
        end
      end
    end

    assert_equal "Custom art direction", captured
  end

  test "custom prompt still skips when fresh processing exists" do
    @meeting.generated_images.create!(status: "processing", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), updated_at: 5.minutes.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, custom_prompt: "Custom art direction")
        end
      end
    end

    assert_equal 1, @meeting.generated_images.where(status: "processing").count
  end

  test "transient failure marks reservation failed so next run retries generation" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }
    fingerprint = GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes)
    @meeting.generated_images.create!(status: "failed", source_content_fingerprint: fingerprint, retry_count: 1, failure_reason: "timeout")
    calls = 0

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::Generator.stub :new, ->(*) do
          calls += 1
          Object.new.tap { |o| o.define_singleton_method(:call) { true } }
        end do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal 1, calls
  end

  test "force bypasses exhausted failure" do
    @meeting.generated_images.create!(status: "failed", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), retry_count: 2)
    captured = nil

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = { custom_prompt: custom_prompt, retrying_after: retrying_after }
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, force: true)
        end
      end
    end

    assert_nil captured[:retrying_after]
  end

  test "force with blank custom prompt marks reservation as admin override" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }
    captured = nil

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = generated_image
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, force: true)
        end
      end
    end

    assert_predicate captured, :admin_override
    assert_nil captured.custom_prompt
  end

  test "force still generates when a ready admin upload exists" do
    @meeting.generated_images.create!(
      status: "ready",
      admin_override: true,
      source_generation_tier: "admin_upload",
      generated_at: Time.current
    )
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }
    captured = nil

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = generated_image
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, force: true)
        end
      end
    end

    assert_predicate captured, :admin_override
    assert_equal 2, @meeting.generated_images.count
  end

  test "force bypasses meeting eligibility checks" do
    eligibility_called = false
    captured = nil

    GeneratedImages::MeetingEligibility.stub :new, ->(*) do
      eligibility_called = true
      raise "should not call auto eligibility when forced"
    end do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
        captured = eligibility
        Object.new.tap { |o| o.define_singleton_method(:call) { true } }
      end do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, force: true)
        end
      end
    end

    assert_equal false, eligibility_called
    assert_predicate captured, :eligible?
    assert_equal false, captured.composite?
  end

  test "force still skips when fresh processing exists" do
    @meeting.generated_images.create!(status: "processing", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), updated_at: 5.minutes.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(*) { raise "should not generate" } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, force: true)
        end
      end
    end

    assert_equal 1, @meeting.generated_images.where(status: "processing").count
  end

  test "expired processing image is failed and replaced" do
    old = @meeting.generated_images.create!(status: "processing", source_content_fingerprint: GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes), updated_at: 2.hours.ago)

    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }
    captured = nil

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) { captured = generated_image; Object.new.tap { |o| o.define_singleton_method(:call) { true } } } do
        GeneratedImages::Config.stub :enabled?, true do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal "failed", old.reload.status
    assert_equal "Processing reservation expired", old.failure_reason
    assert_not_nil captured
  end

  test "uses preferred usable summary by priority and recency" do
    @packet.update_columns(updated_at: 2.days.ago)
    newer_packet = @meeting.meeting_summaries.create!(summary_type: "packet_analysis", content: "", generation_data: { "headline" => "Newer packet headline about stormwater and street repairs.", "highlights" => [ { "text" => "Stormwater and street repairs" } ], "item_details" => [] })
    @minutes.update!(content: "", generation_data: {})

    captured_summary = nil
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) do
      Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false)
    end

    generator_obj = Object.new
    generator_obj.define_singleton_method(:call) { true }

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::MeetingEligibility.stub :new, ->(*args, summary:) { captured_summary = summary; eligibility_obj } do
        GeneratedImages::Generator.stub :new, ->(*) { generator_obj } do
          GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
        end
      end
    end

    assert_equal newer_packet, captured_summary
  end

  test "custom prompt forces generation even with matching fingerprint" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }
    captured = nil

    GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
      @meeting.stub :generated_images, @meeting.generated_images.ready do
        GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
          captured = { imageable: imageable, source: source, eligibility: eligibility, custom_prompt: custom_prompt }
          Object.new.tap { |o| o.define_singleton_method(:call) { true } }
        end do
          GeneratedImages::Config.stub :enabled?, true do
            GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id, custom_prompt: "Custom art direction")
          end
        end
      end
    end

    assert_equal "Custom art direction", captured[:custom_prompt]
  end

  test "generic failed generation enqueues one retry" do
    eligibility_obj = Object.new
    eligibility_obj.define_singleton_method(:call) { Struct.new(:eligible?, :reason, :primary_text, :composite?).new(true, nil, "street repairs", false) }
    fingerprint = GeneratedImages::ContentFingerprint.for_meeting_summary(@minutes)
    first_result = nil
    call_count = 0

    GeneratedImages::Config.stub :enabled?, true do
      GeneratedImages::MeetingEligibility.stub :new, ->(*) { eligibility_obj } do
        GeneratedImages::Generator.stub :new, ->(imageable, source:, eligibility:, custom_prompt: nil, generated_image: nil, retrying_after: nil) do
          call_count += 1
          if call_count == 1
            first_result = imageable.generated_images.create!(status: "failed", source_content_fingerprint: fingerprint, retry_count: 1, failure_reason: "generic failure")
            Object.new.tap { |o| o.define_singleton_method(:call) { first_result } }
          else
            Object.new.tap { |o| o.define_singleton_method(:call) { true } }
          end
        end do
          assert_enqueued_with(job: GeneratedImages::GenerateForMeetingJob, args: [ @meeting.id, { custom_prompt: nil, force: false } ]) do
            GeneratedImages::GenerateForMeetingJob.perform_now(@meeting.id)
          end
        end
      end
    end

    assert_equal 1, call_count
    assert_equal 1, @meeting.generated_images.where(status: "failed").maximum(:retry_count)
  end
end
