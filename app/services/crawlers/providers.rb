module Crawlers
  module Providers
    # Only operator-published crawler feeds belong here, never general cloud IPs.
    # Perplexity documents the feeds at perplexity.com, which 302 to these
    # perplexity.ai URLs. IpRanges rejects redirects, same as the other
    # operators, so the stored URLs are the ones that return 200.
    # Docs: https://docs.perplexity.ai/docs/resources/perplexity-crawlers
    FEEDS = {
      google: "https://developers.google.com/static/crawling/ipranges/common-crawlers.json",
      bing: "https://www.bing.com/toolbox/bingbot.json",
      openai_search: "https://openai.com/searchbot.json",
      openai_user: "https://openai.com/chatgpt-user.json",
      anthropic: "https://claude.com/crawling/bots.json",
      perplexity_bot: "https://www.perplexity.ai/perplexitybot.json",
      perplexity_user: "https://www.perplexity.ai/perplexity-user.json"
    }.freeze

    BOTS = {
      "Googlebot" => :google,
      "Google-InspectionTool" => :google,
      "bingbot" => :bing,
      "OAI-SearchBot" => :openai_search,
      "ChatGPT-User" => :openai_user,
      "Claude-SearchBot" => :anthropic,
      "Claude-User" => :anthropic,
      "PerplexityBot" => :perplexity_bot,
      "Perplexity-User" => :perplexity_user
    }.freeze
  end
end
