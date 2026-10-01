require "ipaddr"

# These are network peers allowed to supply X-Forwarded-For, not crawlers.
# Keep the application port private and expose only the proxy, which appends
# its observed client IP. Never trust a browser-supplied bot-verification header.
Rails.application.config.x.crawler_trusted_proxies = ENV.fetch(
  "CRAWLER_TRUSTED_PROXY_CIDRS", "127.0.0.1/32,::1/128,172.16.0.0/12"
).split(",").map { |prefix| IPAddr.new(prefix.strip) }.freeze
