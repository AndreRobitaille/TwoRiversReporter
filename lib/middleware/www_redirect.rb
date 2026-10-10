# Sends www.tworiversmatters.com to the apex, preserving path and query.
# kamal-proxy must present a certificate for www before this runs; until the
# next deploy that adds www to proxy.hosts, TLS still fails at the proxy.
class WwwRedirect
  APEX_HOST = "tworiversmatters.com"

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) unless request.host.casecmp?("www.#{APEX_HOST}")

    location = "https://#{APEX_HOST}#{request.fullpath}"
    [
      301,
      { "Location" => location, "Content-Type" => "text/html; charset=utf-8", "Cache-Control" => "public, max-age=3600" },
      [ %(<html><body>Redirecting to <a href="#{Rack::Utils.escape_html(location)}">#{Rack::Utils.escape_html(location)}</a></body></html>) ]
    ]
  end
end
