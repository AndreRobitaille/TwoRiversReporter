module Ai
  class OpenAiService
    # Updated to GPT-5.2 as requested
    DEFAULT_MODEL = ENV.fetch("OPENAI_REASONING_MODEL", "gpt-5.2")

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
        <extraction_spec>
        Classify agenda items into high-level topics.

        Schema:
        {
          "items": [
            {#{' '}
              "id": 123,#{' '}
              "category": "Infrastructure|Public Safety|Parks & Rec|Finance|Zoning|Licensing|Personnel|Governance|Other",#{' '}
              "tags": ["Tag1", "Tag2"]#{' '}
            }
          ]
        }
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

    # PASS 1: Analysis & Planning
    def analyze_meeting_content(doc_text, kb_context, type)
      system_role = "You are an investigative civic data analyst. Your goal is to deeply analyze meeting documents to identify what matters most to residents."

      prompt = <<~PROMPT
        Analyzes the provided #{type} text and return a JSON analysis plan.

        #{kb_context}

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
        - Look for what is *not* said. Glossed-over costs? indefinite timelines?
        - "Decision Hinges" must be factual gaps (e.g. "Maintenance cost source not specified").
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
        - Do not speculate.
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
