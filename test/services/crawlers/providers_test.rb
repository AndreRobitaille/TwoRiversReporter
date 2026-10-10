require "test_helper"

class Crawlers::ProvidersTest < ActiveSupport::TestCase
  test "perplexity feeds are the non-redirecting official JSON endpoints" do
    assert_equal "https://www.perplexity.ai/perplexitybot.json", Crawlers::Providers::FEEDS.fetch(:perplexity_bot)
    assert_equal "https://www.perplexity.ai/perplexity-user.json", Crawlers::Providers::FEEDS.fetch(:perplexity_user)
    assert_equal :perplexity_bot, Crawlers::Providers::BOTS.fetch("PerplexityBot")
    assert_equal :perplexity_user, Crawlers::Providers::BOTS.fetch("Perplexity-User")
  end
end
