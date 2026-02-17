module Ai
  class OpenAiService
    # Updated to GPT-5.2 as requested
    DEFAULT_MODEL = ENV.fetch("OPENAI_REASONING_MODEL", "gpt-5.2")
    DEFAULT_GEMINI_MODEL = ENV.fetch("GEMINI_MODEL", "gemini-3-pro-preview")

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

    def extract_votes(text)
      prompt = <<~PROMPT
        <extraction_spec>
        You are a data extraction assistant. Extract formal motions and voting records from meeting minutes into JSON.

        - Always follow this schema exactly (no extra fields).
        - If a field is not present, set it to null.
        - Before returning, re-scan to ensure no motions were missed.

        Schema:
        {
          "motions": [
            {
              "description": "Text of the motion (e.g. 'Motion to approve the minutes')",
              "outcome": "passed" | "failed" | "tabled" | "other",
              "votes": [
                { "member": "Member Name", "value": "yes" | "no" | "abstain" | "absent" | "recused" }
              ]
            }
          ]
        }
        </extraction_spec>

        <ambiguity_handling>
        - For "roll call" votes, list every member.
        - For "voice votes", leave "votes" empty unless exceptions are named.
        - Infer "yes" from "Present" members on unanimous votes ONLY if confident.
        </ambiguity_handling>

        Text:
        #{text.truncate(50000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: "You are a data extraction assistant." },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )
      response.dig("choices", 0, "message", "content")
    end

    def extract_topics(items_text)
      prompt = <<~PROMPT
        <governance_constraints>
        - Topics are long-lived civic concerns that may span multiple meetings, bodies, and extended periods.
        - Prefer agenda items as structural anchors for topic detection.
        - Distinguish routine procedural items from substantive civic issues.
        - If confidence in topic classification is low, set confidence below 0.5 and classify as "Other".
        - Do not infer motive or speculate about intent behind agenda item placement or wording.
        </governance_constraints>

        <extraction_spec>
        Classify agenda items into high-level topics. Return JSON matching the schema below.

        - Ignore "Minutes of Meetings" items if they refer to *previous* meetings (e.g. "Approve minutes of X"). Classify these as "Administrative".
        - Do NOT extract topics from the titles of previous meeting minutes (e.g. if item is "Minutes of Public Works", do not tag "Public Works").
        - If an item is purely administrative (Call to Order, Roll Call, Adjournment), classify as "Administrative".

        Schema:
        {
          "items": [
            {
              "id": 123,
              "category": "Infrastructure|Public Safety|Parks & Rec|Finance|Zoning|Licensing|Personnel|Governance|Other|Administrative",
              "tags": ["Tag1", "Tag2"],
              "confidence": 0.9
            }
          ]
        }

        - "confidence" must be between 0.0 and 1.0.
        - Use high confidence (>= 0.8) for clear, unambiguous civic topics.
        - Use low confidence (< 0.5) for items where the topic is unclear or could be procedural.
        </extraction_spec>

        Text:
        #{items_text.truncate(50000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: "You are a civic data classifier." },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )
      response.dig("choices", 0, "message", "content")
    end

    def triage_topics(context_json)
      prompt = <<~PROMPT
        You are assisting a civic transparency system. Propose topic merges, approvals, and procedural blocks.

        <governance_constraints>
        - Topic Governance is binding.
        - Prefer resident-facing canonical topics over granular variations (e.g., "Alcohol licensing" over "Beer"/"Wine").
        - Do NOT merge if scope is ambiguous or evidence conflicts.
        - Procedural/admin items should be blocked (Roberts Rules, roll call, adjournment, agenda approval, minutes).
        </governance_constraints>

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

      if use_gemini?
        gemini_generate(prompt, temperature: 0.1)
      else
        response = @client.chat(
          parameters: {
            model: DEFAULT_MODEL,
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: "You are a careful civic topic triage assistant." },
              { role: "user", content: prompt }
            ],
            temperature: 0.1
          }
        )

        response.dig("choices", 0, "message", "content")
      end
    end

    def analyze_topic_summary(context_json)
      system_role = "You are a civic continuity analyst. Your goal is to separate factual record from institutional framing and civic sentiment."

      prompt = <<~PROMPT
        Analyze the provided Topic Context and return a JSON analysis plan.

        <governance_constraints>
        - Topic Governance is binding.
        - Factual Record: Must have citations. If no document evidence, do not state as fact.
        - Institutional Framing: Label staff summaries/titles as framing, not truth.
        - Civic Sentiment: Use observational language ("appears to", "residents expressed"). No unanimity claims.
        - Continuity: Explicitly note recurrence, deferrals, and cross-body progression.
        </governance_constraints>

        TOPIC CONTEXT (JSON):
        #{context_json.to_json}

        <citation_rules>
        - You must include citations for all claims in "factual_record" and "institutional_framing".
        - Use the "citation_id" provided in the input context (e.g. "doc-123").
        - The "citations" array in the output should contain objects: { "citation_id": "doc-123", "label": "Packet Page 12" }.
        - If no citation is available for a claim, do not include it in the factual record.
        </citation_rules>

        <resident_reported_rules>
        - If "resident_reported_context" is present in the input, include it only in the "resident_reported_context" section.
        - Never place resident-reported information into factual_record.
        - Always preserve the label "Resident-reported (no official record)".
        </resident_reported_rules>

        <extraction_spec>
        Return a JSON object matching this schema exactly.

        Schema:
        {
          "topic_name": "Canonical name",
          "lifecycle_status": "active|dormant|resolved|recurring",
          "factual_record": [
            { "statement": "Verified claim.", "citations": [{ "citation_id": "...", "label": "..." }] }
          ],
          "institutional_framing": [
             { "statement": "How the city frames this.", "source": "Staff Summary", "citations": [{ "citation_id": "...", "label": "..." }] }
          ],
          "civic_sentiment": [
             { "observation": "Observed resident feedback.", "evidence": "Public Comment", "citations": [{ "citation_id": "...", "label": "..." }] }
          ],
          "resident_reported_context": [
             { "statement": "Resident-reported context.", "label": "Resident-reported (no official record)" }
          ],
          "continuity_signals": [
             { "signal": "recurrence|deferral|disappearance|cross_body_progression", "details": "Explanation", "citations": [{ "citation_id": "...", "label": "..." }] }
          ],
          "decision_hinges": ["Unknowns or key dependencies"],
          "ambiguities": ["Conflicting info"],
          "verification_notes": ["What to check"]
        }
        </extraction_spec>
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: system_role },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )

      response.dig("choices", 0, "message", "content")
    end

    def render_topic_summary(plan_json)
      system_role = "You are a civic engagement assistant. Write a Topic-First summary."

      prompt = <<~PROMPT
        Using the provided TOPIC ANALYSIS (JSON), write a Markdown summary for this Topic's appearance in the meeting.

        <style_guide>
        - Heading 2 (##) for the Topic Name.
        - Section: **Factual Record** (Bulleted). Append citations like [Packet Page 12].
        - Section: **Institutional Framing** (Bulleted).
        - Section: **Civic Sentiment** (Bulleted, if any).
        - Section: **Resident-reported (no official record)** (Bulleted, if any).
        - Section: **Continuity** (If signals exist).
        - Do NOT mix these categories.
        - If a section is empty, omit it (except Factual Record, which should note "No new factual record" if empty).
        </style_guide>

        <citation_rendering>
        - When rendering citations, use the "label" field from the citation object.
        - Format: Statement [Label].
        </citation_rendering>

        <resident_reported_rendering>
        - If resident_reported_context is present, render it under the exact heading:
          **Resident-reported (no official record)**.
        - Do not add citations to this section.
        </resident_reported_rendering>

        INPUT (JSON):
        #{plan_json}
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          messages: [
            { role: "system", content: system_role },
            { role: "user", content: prompt }
          ],
          temperature: 0.2
        }
      )

      response.dig("choices", 0, "message", "content")
    end

    private

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

    # PASS 1: Analysis & Planning
    def analyze_meeting_content(doc_text, kb_context, type)
      system_role = "You are an investigative civic data analyst. Your goal is to deeply analyze meeting documents to identify what matters most to residents."

      prompt = <<~PROMPT
        Analyze the provided #{type} text and return a JSON analysis plan.

        #{kb_context}

        <governance_constraints>
        - Do not assign motive or speculate about intent.
        - Treat staff summaries, agenda item titles, and recommended actions as institutional framing, not neutral truth.
        - Decision hinges must be factual gaps (e.g. "Maintenance cost source not specified"), not editorial judgments.
        - Describe what is observable. Do not editorialize.
        </governance_constraints>

        <long_context_handling>
        - The document text below may be long.
        - First, internally scan for: Financial commitments, Regulatory changes, and "Decision Hinges" (unknowns).
        - Anchor your analysis to specific sections or pages.
        </long_context_handling>

        DOCUMENT TEXT:
        #{doc_text.truncate(100000)}

        <extraction_spec>
        Structure the output as a JSON object matching this schema exactly.

        Schema:
        {
          "top_topics": [
            {
              "title": "Short descriptive title",
              "impact_level": "High|Medium|Low",
              "description": "One sentence summary.",
              "why_it_matters": "Plain language explanation of resident impact.",
              "key_details": "Specifics: $ amounts, dates, votes required.",
              "citations": ["Page X"]
            }
          ],
          "other_topics": [
            { "title": "Topic Name", "summary": "Very brief summary." }
          ],
          "framing_notes": [
            "Observation about how the city presents or frames an issue (e.g. staff summary language, recommended action wording)."
          ],
          "public_comments": [
            { "speaker": "Name", "summary": "What they said (Address redacted)." }
          ],
          "decision_hinges": [
            "Statement of a key unknown or critical verification point."
          ],
          "official_discussion": [
             "Key point raised by a council member (if applicable)."
          ]
        }
        </extraction_spec>

        <investigative_guidelines>
        - Note costs, timelines, or details that are not explicitly stated in the document.
        - "Decision Hinges" must be factual gaps, not speculation about why information is missing.
        - Redact all residential addresses in public comments: "[Address redacted]".
        </investigative_guidelines>
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: system_role },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )

      response.dig("choices", 0, "message", "content")
    end

    # PASS 2: Rendering
    def render_meeting_summary(doc_text, plan_json, type)
      system_role = "You are a civic engagement assistant for Two Rivers, WI. Write clear, neutral, truth-seeking summaries."

      prompt = <<~PROMPT
        Using the provided ANALYSIS PLAN (JSON), write a final Markdown summary.

        <output_verbosity_spec>
        - Follow the structure below EXACTLY.
        - TL;DR: Max 3 bullets.
        - Top Topics: Max 5 items.
        - Other Topics: 1 line per item.
        - Public Comment: Summarize key points, keep it neutral.
        - Use standard Markdown headers (##, ###).
        </output_verbosity_spec>

        <structure_enforcement>
        ## TL;DR (Highest impact first)
        (Bulleted list of top 3 critical items. Include citations [Page X].)

        ## Top Topics (Detailed)
        (Iterate 'top_topics'. Format:)
        ### 1) [Title] — Impact: [Level]
        *   **Proposal:** [Description] [Citations]
        *   **Why it matters:** [Why It Matters]
        *   **Key Details:** [Key Details]

        ## Other Topics (Brief)
        (Bulleted list of 'other_topics'.)

        ## Institutional Framing
        (If 'framing_notes' exist, render as a bulleted list. These are observations about how the city presents or frames issues — not neutral facts. Omit this section if empty.)

        ## Public Comment
        (Summarize 'public_comments'. Redact addresses.)

        ## Official Discussion
        (Summarize 'official_discussion'.)

        ## Decision Hinges (Key Unknowns)
        (Bulleted list of 'decision_hinges'.)

        ## Verification Notes
        (List documents/pages to check.)
        </structure_enforcement>

        <uncertainty_and_ambiguity>
        - Do not speculate. Do not assign motive or infer intent. Describe what is observable.
        - Treat staff recommendations and agenda titles as institutional framing, not neutral description.
        - If a detail is missing in the JSON plan, do not invent it.
        - Use "Not specified" for missing data.
        </uncertainty_and_ambiguity>

        INPUTS:
        ANALYSIS PLAN (JSON):
        #{plan_json}

        ORIGINAL TEXT (For reference):
        #{doc_text.truncate(50000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: DEFAULT_MODEL,
          messages: [
            { role: "system", content: system_role },
            { role: "user", content: prompt }
          ],
          temperature: 0.2
        }
      )

      response.dig("choices", 0, "message", "content")
    end
  end
end
