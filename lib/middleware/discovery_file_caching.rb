class DiscoveryFileCaching
  PATHS = %w[/robots.txt /llms.txt].freeze
  CACHE_CONTROL = "public, max-age=3600, must-revalidate".freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    if PATHS.include?(env["PATH_INFO"]) && %w[GET HEAD].include?(env["REQUEST_METHOD"]) && [ 200, 304 ].include?(status)
      headers["cache-control"] = CACHE_CONTROL
    end
    [ status, headers, body ]
  end
end
