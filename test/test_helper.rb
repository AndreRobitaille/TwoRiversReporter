ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    # fixtures :all

    # Simple mock helper if needed
    def stub_request(url, headers = {}, &block)
      # Implementation depends on needs, but maybe we just use Minitest::Mock in individual tests
    end

    # Seeds prompt templates needed by OpenAiService.
    # Loads the seed data and the populate rake task data.
    # Call in setup for tests that exercise OpenAiService methods.
    def seed_prompt_templates
      return if PromptTemplate.count >= 16

      require_relative "support/prompt_template_seeds"
      PromptTemplateSeeds.create_all!
    end
  end
end
