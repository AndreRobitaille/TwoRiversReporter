module Crawlers
  module Providers
    # Only operator-published crawler feeds belong here, never general cloud IPs.
    FEEDS = {
      google: "https://developers.google.com/static/crawling/ipranges/common-crawlers.json",
      bing: "https://www.bing.com/toolbox/bingbot.json"
    }.freeze

    BOTS = {
      "Googlebot" => :google,
      "Google-InspectionTool" => :google,
      "bingbot" => :bing
    }.freeze
  end
end
