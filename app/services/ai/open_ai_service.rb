module Ai
  class OpenAiService
    # Updated to GPT-5.2 as requested
    DEFAULT_MODEL = ENV.fetch("OPENAI_REASONING_MODEL", "gpt-5.2")
    DEFAULT_GEMINI_MODEL = ENV.fetch("GEMINI_MODEL", "gemini-3-pro-preview")
    LIGHTWEIGHT_MODEL = ENV.fetch("OPENAI_LIGHTWEIGHT_MODEL", "gpt-5-mini")

    def initialize
      @client = OpenAI::Client.new(access_token: Rails.application.credentials.openai_access_token || ENV["OPENAI_ACCESS_TOKEN"])
    end

    # Two-pass summary for packets
    def summarize_packet_with_citations(extractions, context_chunks: [])
      doc_context = prepare_doc_context(extractions)
      kb_context = prepare_kb_context(context_chunks)

      # Pass 1: Planning / Analysis (JSON)
      plan_json = analyze_meeting_content(doc_context, kb_context, "packet")

      # Pass 2: Rendering (Markdown)
      render_meeting_summary(doc_context, plan_json, "packet")
    end

    def summarize_packet(text, context_chunks: [])
      kb_context = prepare_kb_context(context_chunks)
      plan_json = analyze_meeting_content(text, kb_context, "packet")
      render_meeting_summary(text, plan_json, "packet")
    end

    def summarize_minutes(text, context_chunks: [])
      kb_context = prepare_kb_context(context_chunks)
      plan_json = analyze_meeting_content(text, kb_context, "minutes")
      render_meeting_summary(text, plan_json, "minutes")
    end

    def extract_votes(text, source: nil)
      template = PromptTemplate.find_by!(key: "extract_votes")
      system_role = template.system_role
      placeholders = { text: text.truncate(50_000) }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "extract_votes",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def extract_committee_members(text, source: nil)
      template = PromptTemplate.find_by!(key: "extract_committee_members")
      system_role = template.system_role
      placeholders = { text: text.truncate(50_000) }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "extract_committee_members",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def extract_topics(items_text, community_context: "", existing_topics: [], meeting_documents_context: "", source: nil)
      existing_topics_list = existing_topics.join("\n")

      template = PromptTemplate.find_by!(key: "extract_topics")
      system_role = template.system_role
      placeholders = {
        items_text: items_text.truncate(50_000),
        community_context: community_context,
        existing_topics: existing_topics_list,
        meeting_documents_context: meeting_documents_context.to_s.truncate(30_000, separator: " ")
      }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "extract_topics",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def refine_catchall_topic(item_title:, item_summary:, catchall_topic:, document_text:, existing_topics: [], source: nil)
      template = PromptTemplate.find_by!(key: "refine_catchall_topic")
      system_role = template.system_role
      placeholders = {
        item_title: item_title,
        item_summary: item_summary.to_s,
        catchall_topic: catchall_topic,
        document_text: document_text.to_s.truncate(6000, separator: " "),
        existing_topics: existing_topics.join(", ")
      }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "refine_catchall_topic",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def re_extract_item_topics(item_title:, item_summary:, document_text:, broad_topic_name:, existing_topics: [], source: nil)
      template = PromptTemplate.find_by!(key: "re_extract_item_topics")
      system_role = template.system_role
      placeholders = {
        item_title: item_title,
        item_summary: item_summary.to_s,
        document_text: document_text.to_s.truncate(6000, separator: " "),
        broad_topic_name: broad_topic_name,
        existing_topics: existing_topics.join(", ")
      }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "re_extract_item_topics",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def triage_topics(context_json, source: nil)
      community_context = context_json.delete(:community_context) || context_json.delete("community_context") || ""

      if use_gemini?
        community_section = if community_context.present?
          "\n<community_context>\nUse this context about Two Rivers residents to inform your approval and blocking decisions. Topics that matter to residents should be approved; routine institutional items should be blocked.\n#{community_context}\n</community_context>\n"
        else
          ""
        end

        prompt = <<~PROMPT
          You are assisting a civic transparency system. Propose topic merges, approvals, and procedural blocks.

          <governance_constraints>
          - Topic Governance is binding.
          - Prefer resident-facing canonical topics over granular variations (e.g., "Alcohol licensing" over "Beer"/"Wine").
          - Do NOT merge if scope is ambiguous or evidence conflicts.
          - Procedural/admin items should be blocked (Roberts Rules, roll call, adjournment, agenda approval, minutes).
          </governance_constraints>
          #{community_section}
          <input>
          The JSON includes:
          - topics: list of topic records with recent agenda items.
          - similarity_candidates: suggested similar topics.
          - procedural_keywords: keywords that indicate procedural items.
          </input>

          <output_schema>
          Return JSON with the exact schema below.
          {
            "merge_map": [
              { "canonical": "Topic Name", "aliases": ["Alt1", "Alt2"], "confidence": 0.0, "rationale": "..." }
            ],
            "approvals": [
              { "topic": "Topic Name", "approve": true, "confidence": 0.0, "rationale": "..." }
            ],
            "blocks": [
              { "topic": "Topic Name", "block": true, "confidence": 0.0, "rationale": "..." }
            ]
          }
          </output_schema>

          <rules>
          - "confidence" must be between 0.0 and 1.0.
          - Only include items you are confident about.
          - If unsure, omit the entry.
          - Rationale should be short and cite the evidence signals (agenda items/titles).
          </rules>

          INPUT JSON:
          #{context_json.to_json}
        PROMPT

        gemini_generate(prompt, temperature: 0.1)
      else
        template = PromptTemplate.find_by!(key: "triage_topics")
        system_role = template.system_role
        placeholders = { context_json: context_json.to_json }
        prompt = template.interpolate(**placeholders)
        model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

        messages = [
          (system_role.present? ? { role: "system", content: system_role } : nil),
          { role: "user", content: prompt }
        ].compact

        start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        response = @client.chat(
          parameters: {
            model: model,
            response_format: { type: "json_object" },
            messages: messages,
            temperature: 0.1
          }
        )
        duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

        content = response.dig("choices", 0, "message", "content")

        record_prompt_run(
          template_key: "triage_topics",
          messages: messages,
          response_content: content,
          model: model,
          response_format: "json_object",
          temperature: 0.1,
          duration_ms: duration_ms,
          source: source,
          placeholder_values: placeholders.transform_keys(&:to_s)
        )

        content
      end
    end

    def analyze_topic_summary(context_json, source: nil)
      template = PromptTemplate.find_by!(key: "analyze_topic_summary")
      committee_ctx = prepare_committee_context
      system_role = template.interpolate_system_role(committee_context: committee_ctx)
      placeholders = { committee_context: committee_ctx, context_json: context_json.to_json }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        { role: "system", content: system_role },
        { role: "user", content: prompt }
      ]

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "analyze_topic_summary",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def render_topic_summary(plan_json, source: nil)
      template = PromptTemplate.find_by!(key: "render_topic_summary")
      system_role = template.interpolate_system_role
      placeholders = { plan_json: plan_json.to_s }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        { role: "system", content: system_role },
        { role: "user", content: prompt }
      ]

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          messages: messages,
          temperature: 0.2
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "render_topic_summary",
        messages: messages,
        response_content: content,
        model: model,
        temperature: 0.2,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def analyze_topic_briefing(context, source: nil)
      template = PromptTemplate.find_by!(key: "analyze_topic_briefing")
      committee_ctx = prepare_committee_context
      system_role = template.interpolate_system_role(committee_context: committee_ctx)
      placeholders = { committee_context: committee_ctx, context: context.to_json }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        { role: "system", content: system_role },
        { role: "user", content: prompt }
      ]

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "analyze_topic_briefing",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def render_topic_briefing(analysis_json, source: nil)
      template = PromptTemplate.find_by!(key: "render_topic_briefing")
      system_role = template.interpolate_system_role
      placeholders = { analysis_json: analysis_json.to_s }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        { role: "system", content: system_role },
        { role: "user", content: prompt }
      ]

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.2
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "render_topic_briefing",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.2,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      JSON.parse(content)
    rescue JSON::ParserError
      { "editorial_content" => "", "record_content" => "" }
    end

    def generate_briefing_interim(context, source: nil)
      template = PromptTemplate.find_by!(key: "generate_briefing_interim")
      system_role = template.system_role
      placeholders = {
        topic_name: context[:topic_name].to_s,
        current_headline: context[:current_headline].to_s,
        meeting_body: context[:meeting_body].to_s,
        meeting_date: context[:meeting_date].to_s,
        agenda_items: context[:agenda_items].to_json
      }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "generate_briefing_interim",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      JSON.parse(content)
    rescue JSON::ParserError
      { "headline" => context[:current_headline], "upcoming_note" => "" }
    end

    def generate_topic_description(topic_context, source: nil)
      topic_name = topic_context[:topic_name]
      agenda_items = topic_context[:agenda_items] || []
      headlines = topic_context[:headlines] || []

      activity_text = agenda_items.map { |ai| "- #{ai[:title]}#{ai[:summary].present? ? ": #{ai[:summary]}" : ""}" }.join("\n")
      headlines_text = headlines.any? ? "\nRecent headlines:\n#{headlines.map { |h| "- #{h}" }.join("\n")}" : ""

      key = agenda_items.size >= 3 ? "generate_topic_description_detailed" : "generate_topic_description_broad"
      template = PromptTemplate.find_by!(key: key)
      system_role = template.system_role
      placeholders = { topic_name: topic_name, activity_text: activity_text, headlines_text: headlines_text }
      user_prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        (system_role.present? ? { role: "system", content: system_role } : nil),
        { role: "user", content: user_prompt }
      ].compact

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          messages: messages
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: key,
        messages: messages,
        response_content: content,
        model: model,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content.present? ? content.strip : nil
    end

    # Structured meeting analysis — produces JSON for direct rendering.
    # Called by SummarizeMeetingJob to store structured JSON in generation_data.
    def analyze_meeting_content(doc_text, kb_context, type, source: nil)
      template = PromptTemplate.find_by!(key: "analyze_meeting_content")
      committee_ctx = prepare_committee_context
      system_role = template.interpolate_system_role(committee_context: committee_ctx)
      body_name = source.respond_to?(:body_name) ? source.body_name.to_s : ""
      meeting_date = source.respond_to?(:starts_at) ? source.starts_at&.to_date : nil
      today = Date.current

      temporal_framing = if meeting_date && meeting_date > today
                           "preview"
                         elsif type.to_s == "minutes" || type.to_s == "transcript"
                           "recap"
                         else
                           "stale_preview"
                         end

      placeholders = {
        kb_context: kb_context.to_s,
        committee_context: committee_ctx,
        type: type.to_s,
        body_name: body_name,
        meeting_date: meeting_date.to_s,
        today: today.to_s,
        temporal_framing: temporal_framing,
        doc_text: doc_text.truncate(100_000)
      }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        { role: "system", content: system_role },
        { role: "user", content: prompt }
      ]

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          response_format: { type: "json_object" },
          messages: messages,
          temperature: 0.1
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "analyze_meeting_content",
        messages: messages,
        response_content: content,
        model: model,
        response_format: "json_object",
        temperature: 0.1,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end

    def prepare_doc_context(extractions)
      extractions.sort_by(&:page_number).map do |ex|
        "--- [Page #{ex.page_number}] ---\n#{ex.cleaned_text}"
      end.join("\n\n")
    end

    def prepare_kb_context(chunks)
      return "" if chunks.empty?
      <<~CONTEXT
        <context_handling>
        ### Relevant Context (Background Knowledge)
        The following information comes from the city knowledgebase.
        Use it to identify glossed-over details, but distinguish it from document content.

        #{chunks.join("\n\n")}
        </context_handling>
      CONTEXT
    end

    private

    def prepare_committee_context
      committees = Committee.for_ai_context
      return "" if committees.empty?

      lines = committees.map do |c|
        type_label = c.committee_type.humanize
        "- #{c.name} (#{type_label}): #{c.description}"
      end

      <<~CONTEXT
        <local_governance>
        The following committees and boards operate in Two Rivers:
        #{lines.join("\n")}

        Notes:
        - Cross-body movement (topic appearing at different committees) is routine and NOT noteworthy unless City Council sends something BACK DOWN to a subcommittee — that's a signal of disagreement or unresolved issues.
        </local_governance>
      CONTEXT
    end

    def record_prompt_run(template_key:, messages:, response_content:, model:, response_format: nil, temperature: nil, duration_ms: nil, source: nil, placeholder_values: nil)
      PromptRun.create!(
        prompt_template_key: template_key,
        ai_model: model,
        messages: messages,
        response_body: response_content,
        response_format: response_format,
        temperature: temperature,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholder_values
      )
    rescue => e
      Rails.logger.warn("Failed to record prompt run for #{template_key}: #{e.message}")
    end

    def gemini_api_key
      Rails.application.credentials.gemini_access_token || ENV["GEMINI_ACCESS_TOKEN"]
    end

    def use_gemini?
      ENV["USE_GEMINI"] == "true" && gemini_api_key.present?
    end

    def gemini_generate(prompt, temperature: 0.1)
      conn = Faraday.new(url: "https://generativelanguage.googleapis.com", request: { open_timeout: 10, timeout: 240 })
      response = conn.post("/v1beta/models/#{DEFAULT_GEMINI_MODEL}:generateContent") do |req|
        req.params["key"] = gemini_api_key
        req.headers["Content-Type"] = "application/json"
        req.body = {
          contents: [
            { role: "user", parts: [ { text: prompt } ] }
          ],
          generationConfig: {
            temperature: temperature,
            response_mime_type: "application/json"
          }
        }.to_json
      end

      unless response.success?
        raise "Gemini request failed: status=#{response.status} body=#{response.body}"
      end

      data = JSON.parse(response.body)
      text = data.dig("candidates", 0, "content", "parts", 0, "text")
      return text if text.present?

      raise "Gemini response missing content: #{response.body}"
    end

    # PASS 2: Rendering (legacy — used by summarize_minutes/packet wrappers)
    def render_meeting_summary(doc_text, plan_json, type, source: nil)
      template = PromptTemplate.find_by!(key: "render_meeting_summary")
      system_role = template.interpolate_system_role
      placeholders = { plan_json: plan_json.to_s, doc_text: doc_text.truncate(50_000) }
      prompt = template.interpolate(**placeholders)
      model = template.model_tier == "lightweight" ? LIGHTWEIGHT_MODEL : DEFAULT_MODEL

      messages = [
        { role: "system", content: system_role },
        { role: "user", content: prompt }
      ]

      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      response = @client.chat(
        parameters: {
          model: model,
          messages: messages,
          temperature: 0.2
        }
      )
      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) * 1000).round

      content = response.dig("choices", 0, "message", "content")

      record_prompt_run(
        template_key: "render_meeting_summary",
        messages: messages,
        response_content: content,
        model: model,
        temperature: 0.2,
        duration_ms: duration_ms,
        source: source,
        placeholder_values: placeholders.transform_keys(&:to_s)
      )

      content
    end
  end
end
