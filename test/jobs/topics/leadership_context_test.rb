require "test_helper"

class Topics::LeadershipContextTest < ActiveJob::TestCase
  test "existing briefing pipeline carries background without publishing its contributor as a source" do
    seed_prompt_templates
    topic = Topic.create!(name: "Sample manager leave and oversight", status: "approved")
    meeting = Meeting.create!(body_name: "City Council", starts_at: 1.day.ago,
      detail_page_url: "https://example.com/leadership-meeting")
    item = meeting.agenda_items.create!(title: "Management-level performance and conduct", order_index: 1)
    item.topics << topic

    notes = [
      "The manager is on paid administrative leave pending investigation; start date unverified.",
      "Supplied messages describe a request to a subordinate chief; dispatch outcome unknown.",
      "Petition withdrawal followed backlash; minutes record withdrawal without a reason.",
      "Editorial scope: develop a connected account. Supervisory access may be improper; no misconduct finding is supplied.",
      "The manager's signed opinion column criticizes the shop owner over an altered image; it is advocacy, not an independent finding."
    ]
    embedder = Object.new
    def embedder.embed(_text) = [ 1.0, 0.0 ]

    Ai::EmbeddingService.stub :new, embedder do
      notes.each_with_index do |body, index|
        source = KnowledgeSource.create!(title: "Leadership context #{index}", body: body,
          source_type: "note", origin: "manual", status: "approved", active: true,
          verification_notes: "Internal contributor: Private Background Editor. Restricted court detail: PRIVATE_COURT_DETAIL_53.",
          stated_at: Date.current)
        source.topics << topic
        IngestKnowledgeSourceJob.perform_now(source.id)
        assert_equal [ body ], source.knowledge_chunks.pluck(:content)
      end

      ai = Ai::OpenAiService.new
      calls = 0
      provider = lambda do |**request|
        calls += 1
        if calls == 1
          prompt = request.fetch(:messages).last.fetch(:content)
          notes.each { |note| assert_includes prompt, note }
          refute_includes prompt, "Private Background Editor"
          refute_includes prompt, "PRIVATE_COURT_DETAIL_53"
          assert_includes prompt, "Honor publication limits in approved background notes"
          assert_includes prompt, "not a public statement by an administrator"
          assert_includes prompt, "Keep background context distinct from the meeting-based `factual_record`"
          assert_includes prompt, "may be improper"
          assert_includes prompt, "<conduct_assessments>"
          assert_includes prompt, "same evidentiary standard to every official"
          assert_includes prompt, "alone is insufficient"
          assert_includes prompt, "frame the headline around the named leadership issue"
          assert_includes prompt, "Cover each materially distinct"
          assert_includes prompt, "about 300-425 words"
          assert_includes prompt, "without that editorial direction, keep the 1-3 sentence default"
          [ {
            headline: "Council reviews management conduct",
            editorial_analysis: { current_state: "The manager is on paid leave pending investigation." },
            factual_record: [], resident_impact: { score: 4 }
          }.to_json, 1 ]
        else
          [ { editorial_content: "A reported leave remains under review.", record_content: "" }.to_json, 1 ]
        end
      end

      ai.stub :call_api, provider do
        Ai::OpenAiService.stub :new, ai do
          Topics::GenerateTopicBriefingJob.perform_now(topic_id: topic.id, meeting_id: meeting.id)
        end
      end
      assert_equal 2, calls
    end

    run = PromptRun.find_by!(source: topic, prompt_template_key: "analyze_topic_briefing")
    context = JSON.parse(run.placeholder_values.fetch("context"))
    assert_equal 5, context.fetch("knowledgebase_context").length
    notes.each do |note|
      assert context.fetch("knowledgebase_context").any? { |chunk| chunk.include?(note) }
    end
    briefing = Topic.find(topic.id).topic_briefing
    assert_equal "The manager is on paid leave pending investigation.",
      briefing.generation_data.dig("editorial_analysis", "current_state")
    assert_empty briefing.generation_data.fetch("factual_record")
  end
end
