require "test_helper"
require_relative "../support/crawler_access_assertions"

class PerplexityCrawlerAccessTest < ActionDispatch::IntegrationTest
  CRAWLERS = [
    {
      feed: :perplexity_bot,
      agent: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; PerplexityBot/1.0; +https://perplexity.ai/perplexitybot)",
      ip: "107.20.236.150",
      prefix: "107.20.236.150/32"
    },
    {
      feed: :perplexity_user,
      agent: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Perplexity-User/1.0; +https://perplexity.ai/perplexity-user)",
      ip: "44.208.221.197",
      prefix: "44.208.221.197/32"
    }
  ].freeze

  include CrawlerAccessAssertions

  test "robots.txt names both Perplexity identities with the other reporting crawlers" do
    get "/robots.txt"

    assert_response :success
    assert_match(/^User-agent: PerplexityBot$/, response.body)
    assert_match(/^User-agent: Perplexity-User$/, response.body)
  end
end
