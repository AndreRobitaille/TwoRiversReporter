# Runs between ConditionalGet and ETag: validators added by Rack must be
# removed before ConditionalGet can turn a private API read into a 304.
class ApiResponseCaching
  def initialize(app)
    @app = app
  end

  def call(env)
    path = env["PATH_INFO"]
    return @app.call(env) unless path.match?(/\A\/api(?:\.[^\/]+)?\z/) || path.start_with?("/api/")

    status, headers, body = begin
      @app.call(env)
    rescue ActionController::RoutingError
      [ 404, {}, [] ]
    end

    headers["cache-control"] = "private, no-store"
    headers["vary"] = "Authorization"
    headers.delete("etag")
    headers.delete("last-modified")
    if status == 404 && !headers["content-type"].to_s.start_with?("application/json")
      body.close if body.respond_to?(:close)
      body = [ JSON.generate(error: { code: "not_found", message: "Content not found." }) ]
      headers["content-type"] = "application/json; charset=utf-8"
      headers.delete("content-length")
    end
    headers.delete("x-cascade") if status == 404
    [ status, headers, body ]
  end
end
