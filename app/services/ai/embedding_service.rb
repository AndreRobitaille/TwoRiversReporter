module Ai
  class EmbeddingService
    def initialize
      @client = OpenAI::Client.new(access_token: Rails.application.credentials.openai_access_token || ENV["OPENAI_ACCESS_TOKEN"])
    end

    def embed(text)
      response = @client.embeddings(
        parameters: {
          model: "text-embedding-3-small",
          input: text
        }
      )

      response.dig("data", 0, "embedding")
    end
  end
end
