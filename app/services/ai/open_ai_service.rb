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
  end
end
