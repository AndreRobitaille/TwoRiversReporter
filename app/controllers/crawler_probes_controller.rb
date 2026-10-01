class CrawlerProbesController < ApplicationController
  allow_unauthenticated_access

  def show
    response.headers["Cache-Control"] = "private, no-store"
    response.headers["X-Robots-Tag"] = "noindex, nofollow"
    @probe = Crawlers::Probe.find(params[:token])
    return head :not_found unless @probe
    return head :not_acceptable unless request.format == Mime[:html]

    Rails.logger.info({
      event: "crawler_probe", token: params[:token], mode: @probe.fetch(:mode),
      request_id: request.request_id, method: request.method,
      full_access: @probe.fetch(:mode) == "public" || !gated_for_visitor?,
      client_ip: Crawlers::ClientIp.new.call(request)&.to_s,
      socket_peer: request.get_header("REMOTE_ADDR"),
      forwarded_for: request.get_header("HTTP_X_FORWARDED_FOR").to_s.first(4096),
      user_agent: request.user_agent.to_s.first(2048)
    }.to_json)

    render layout: false
  end
end
