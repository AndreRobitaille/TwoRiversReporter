require "test_helper"
require_relative "../support/crawler_access_assertions"

class BingCrawlerAccessTest < ActionDispatch::IntegrationTest
  CRAWLERS = [
    { feed: :bing, agent: "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm) Chrome/131.0.0.0 Safari/537.36", ip: "157.55.39.12", prefix: "157.55.39.0/24" }
  ].freeze

  include CrawlerAccessAssertions
end
