module Crawlers
  module Providers
    # Only operator-published crawler feeds belong here, never general cloud IPs.
    FEEDS = {
      google: "https://developers.google.com/static/crawling/ipranges/common-crawlers.json"
    }.freeze

    BOTS = {
      "Googlebot" => :google,
      "Google-InspectionTool" => :google
    }.freeze
  end
end
