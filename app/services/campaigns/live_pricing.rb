require "net/http"

module Campaigns
  # The nightly check only confirms the same public pricing terms used to
  # authorize estimates. A different schedule needs a newly checked rate table.
  class LivePricing
    # SHA-256 of the whitespace-normalized Markdown Pricing section, Nov 21, 2026.
    SECTIONS = {
      "gpt-5.6-luna" => "2bcc4253606e7afb31220f796128cb5af5af49ead66b0c356860be3ac0350d80",
      "gpt-5.6-terra" => "c5b48a068218b75401d262ea9ff3880b51b14132a2479db23ecd9481a8b3c549",
      "gpt-5.6-sol" => "37812511373b2ca2cc08223d62027e53552f790fc5dd8584e721711582d77562"
    }.freeze
    PROMOTION_END = { "gpt-5.6-sol" => Date.new(2026, 11, 30) }.freeze

    def self.refresh
      return if Date.current <= CostPreflight::PRICING_VALID_THROUGH
      month = CouncilAiBudgetMonth.where(revoked_at: nil).find_by(budget_month: Date.current.beginning_of_month)
      model = month&.live_actions&.dig("model")
      return unless SECTIONS.key?(model) && valid_through(model, Date.current) >= Date.current
      return if checked_on(model) == Date.current

      url = URI("#{CostPreflight::PRICING_SOURCE}#{model}.md")
      response = Net::HTTP.start(url.host, url.port, use_ssl: true, open_timeout: 4, read_timeout: 5) { |http| http.get(url.request_uri) }
      section = response.body.to_s[/^## Pricing[ \t]*\n(.*?)(?=^## |\z)/m, 1] if response.is_a?(Net::HTTPSuccess)
      if section && Digest::SHA256.hexdigest(section.squish) == SECTIONS.fetch(model)
        Rails.cache.write(key(model), Date.current.iso8601, expires_in: 2.days)
      else
        Rails.cache.delete(key(model))
        Rails.logger.warn("Campaign pricing could not confirm the approved terms for #{model}")
      end
    rescue Timeout::Error, IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError => e
      Rails.logger.warn("Campaign pricing check unavailable: #{e.class}")
    end

    def self.checked_on(model)
      return unless SECTIONS.key?(model)
      date = Rails.cache.read(key(model))
      return unless date
      checked = Date.iso8601(date)
      checked if Date.current.between?(checked, valid_through(model, checked))
    end

    def self.valid_through(model, checked)
      [ checked + 1.day, PROMOTION_END[model] ].compact.min
    end

    def self.key(model)
      "campaign-pricing/#{model}/#{SECTIONS.fetch(model)}"
    end
    private_class_method :key
  end
end
