require "test_helper"
require_relative "../support/crawler_access_assertions"

class GoogleCrawlerAccessTest < ActionDispatch::IntegrationTest
  CRAWLERS = [
    { feed: :google, agent: "Mozilla/5.0 (compatible; Googlebot/2.1; +http://www.google.com/bot.html)", ip: "66.249.66.1", prefix: "66.249.66.0/27" },
    { feed: :google, agent: "Mozilla/5.0 (compatible; Google-InspectionTool/1.0)", ip: "66.249.66.1", prefix: "66.249.66.0/27" }
  ].freeze

  include CrawlerAccessAssertions
end
