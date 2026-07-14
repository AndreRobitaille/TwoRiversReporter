# Intercepts GET/HEAD requests before Rails routing and issues an HTTP
# redirect when the request path matches a Redirect record. Runs ahead of
# routing so it can redirect paths that still resolve to a live route
# (e.g. /topics/766, where topic 766 was merged away but the route matches).
class RedirectMiddleware
  REDIRECTABLE_METHODS = %w[GET HEAD].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    request = Rack::Request.new(env)

    if REDIRECTABLE_METHODS.include?(request.request_method)
      entry = Redirect.lookup(request.path)
      return redirect_response(entry) if entry
    end

    @app.call(env)
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError
    # Never let a redirect lookup take down the request (e.g. during setup
    # before the table exists).
    @app.call(env)
  end

  private

  def redirect_response(entry)
    Redirect.where(id: entry[:id]).update_all("hits = hits + 1")

    [
      entry[:status_code],
      { "Location" => entry[:destination], "Content-Type" => "text/html", "Cache-Control" => "no-cache" },
      [ redirect_body(entry[:destination]) ]
    ]
  end

  def redirect_body(destination)
    target = Rack::Utils.escape_html(destination)
    %(<html><body>Redirecting to <a href="#{target}">#{target}</a></body></html>)
  end
end
