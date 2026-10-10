require "test_helper"
require_relative "../support/crawler_access_assertions"

class ClaudeCrawlerAccessTest < ActionDispatch::IntegrationTest
  CRAWLERS = [
    { feed: :anthropic, agent: "Claude-SearchBot/1.0", ip: "216.73.216.12", prefix: "216.73.216.0/22" },
    { feed: :anthropic, agent: "Claude-User/1.0", ip: "216.73.216.12", prefix: "216.73.216.0/22" }
  ].freeze

  include CrawlerAccessAssertions
end
