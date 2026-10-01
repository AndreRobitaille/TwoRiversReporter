module Crawlers
  module Providers
    # Only operator-published crawler feeds belong here, never general cloud IPs.
    FEEDS = {
      google: "https://developers.google.com/static/crawling/ipranges/common-crawlers.json",
      bing: "https://www.bing.com/toolbox/bingbot.json",
      openai_search: "https://openai.com/searchbot.json",
      openai_user: "https://openai.com/chatgpt-user.json"
    }.freeze

    BOTS = {
      "Googlebot" => :google,
      "Google-InspectionTool" => :google,
      "bingbot" => :bing,
      "OAI-SearchBot" => :openai_search,
      "ChatGPT-User" => :openai_user
    }.freeze
  end
end
