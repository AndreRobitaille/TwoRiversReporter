require "test_helper"
require_relative "../support/crawler_access_assertions"

class OpenaiCrawlerAccessTest < ActionDispatch::IntegrationTest
  CRAWLERS = [
    { feed: :openai_search, agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36; compatible; OAI-SearchBot/1.4; +https://openai.com/searchbot", ip: "20.171.206.12", prefix: "20.171.206.0/24" },
    { feed: :openai_user, agent: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko); compatible; ChatGPT-User/1.0; +https://openai.com/bot", ip: "23.98.142.178", prefix: "23.98.142.176/28" }
  ].freeze

  include CrawlerAccessAssertions
end
