module Ai
  class OpenAiService
    def initialize
      @client = OpenAI::Client.new(access_token: Rails.application.credentials.openai_access_token || ENV["OPENAI_ACCESS_TOKEN"])
    end

    def summarize_packet(text)
      prompt = <<~PROMPT
        You are a civic engagement assistant for the residents of Two Rivers, WI.
        Your goal is to help residents understand what will be discussed at an upcoming meeting based on the meeting packet.

        The following text is extracted from the meeting packet PDF.
        Please provide a summary of the KEY items that affect residents (e.g., spending, zoning changes, new ordinances).

        Guidelines:
        - Focus on the "Why it matters" for a resident.
        - Ignore routine procedural items (roll call, approval of minutes) unless they contain something unusual.
        - If financial figures are mentioned, include them.
        - Keep the tone neutral and informative.
        - Structure the response with Markdown headers.

        Text to summarize:
        #{text.truncate(50000)} <!-- Truncate to avoid context limit issues initially -->
      PROMPT

      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.3
        }
      )

      response.dig("choices", 0, "message", "content")
    end

    def summarize_packet_with_citations(extractions)
      # Build context with page markers
      context = extractions.sort_by(&:page_number).map do |ex|
        "--- [Page #{ex.page_number}] ---\n#{ex.cleaned_text}"
      end.join("\n\n")

      prompt = <<~PROMPT
        You are a civic engagement assistant for the residents of Two Rivers, WI.
        Your goal is to help residents understand what will be discussed at an upcoming meeting based on the meeting packet.

        The following text is extracted from the meeting packet PDF, organized by page number.
        Please provide a summary of the KEY items that affect residents (e.g., spending, zoning changes, new ordinances).

        Guidelines:
        - Focus on the "Why it matters" for a resident.
        - Ignore routine procedural items (roll call, approval of minutes) unless they contain something unusual.
        - If financial figures are mentioned, include them.
        - Keep the tone neutral and informative.
        - Structure the response with Markdown headers.
        - CRITICAL: You MUST cite the source page for every claim using the format [Page X].
        - Example: "The city plans to purchase a new fire truck for $500,000 [Page 12]."

        Text to summarize:
        #{context.truncate(100000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.3
        }
      )

      response.dig("choices", 0, "message", "content")
    end

    def summarize_minutes(text)
      prompt = <<~PROMPT
        You are a civic engagement assistant for the residents of Two Rivers, WI.
        Your goal is to help residents understand what happened at a past meeting based on the minutes.

        The following text is extracted from the meeting minutes PDF.
        Please provide a recap of the meeting.

        Guidelines:
        - Highlight any specific votes taken (Who voted Yes/No?).
        - Summarize public comments if any were made.
        - Summarize the outcome of key agenda items.
        - Structure the response with Markdown headers.

        Text to summarize:
        #{text.truncate(50000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          messages: [ { role: "user", content: prompt } ],
          temperature: 0.3
        }
      )

      response.dig("choices", 0, "message", "content")
    end
    def extract_votes(text)
      prompt = <<~PROMPT
        You are a data extraction assistant.
        Your goal is to extract formal motions and voting records from meeting minutes.

        The following text is from the meeting minutes.
        Please return a JSON object with a key "motions" containing an array of every motion.

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

        Guidelines:
        - Identify motions where a decision was made.
        - For "roll call" votes, you MUST list every member and their specific vote.
        - For "voice votes" or "unanimous consent", if individual votes are not listed, you may leave the "votes" array empty or include only those explicitly named (e.g. "Smith abstained").
        - If the text lists members "Present" at the start, use those names to infer "yes" votes on unanimous motions ONLY IF you are confident. Otherwise, prefer explicit data.
        - Clean member names (remove "Councilmember", "Mr.", "Ms.", etc. if possible).

        Text:
        #{text.truncate(50000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: "You are a data extraction assistant that outputs JSON." },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )

      response.dig("choices", 0, "message", "content")
    end
    def extract_topics(items_text)
      prompt = <<~PROMPT
        You are a civic data classifier.
        Your goal is to classify agenda items into high-level topics based on their content.

        The text below contains a list of agenda items with their internal IDs.
        For each item, assign:
        1. A primary category (Infrastructure, Public Safety, Parks & Rec, Finance, Zoning, Licensing, Personnel, Governance, Other).
        2. Specific tags (keywords like "Tax Levy", "Short-term Rentals", "Harbor", "Police").

        Return a JSON object:
        {
          "items": [
            { "id": 123, "category": "Finance", "tags": ["Tax Levy", "Budget"] }
          ]
        }

        Text:
        #{items_text.truncate(50000)}
      PROMPT

      response = @client.chat(
        parameters: {
          model: "gpt-4o-mini",
          response_format: { type: "json_object" },
          messages: [
            { role: "system", content: "You are a classifier that outputs JSON." },
            { role: "user", content: prompt }
          ],
          temperature: 0.1
        }
      )

      response.dig("choices", 0, "message", "content")
    end
  end
end
