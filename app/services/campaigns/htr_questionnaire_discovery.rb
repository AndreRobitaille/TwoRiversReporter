require "net/http"

module Campaigns
  class HtrQuestionnaireDiscovery
    Unavailable = Class.new(StandardError)
    Article = Data.define(:url, :published_on)
    NEWS_SITEMAP = "https://www.htrnews.com/news-sitemap.xml"
    ARCHIVE_INDEX = "https://web.archive.org/cdx/search/cdx"

    def self.find(election_on)
      if Date.current <= election_on
        begin
          xml = Nokogiri::XML(fetch(NEWS_SITEMAP)) { |config| config.strict.nonet }
          recent = articles(xml.xpath("//*[local-name()='loc']").map(&:text), election_on)
          return recent if recent.any?
        rescue Unavailable, Nokogiri::XML::SyntaxError
          # HTR can restrict access. The archive indexes the original publisher URLs.
        end
      end

      query = URI.encode_www_form(url: "www.htrnews.com/story/news/politics/elections/#{election_on.year}/",
        matchType: "prefix", filter: "original:.*two-rivers.*candidates?.*", collapse: "urlkey", output: "json", fl: "original", limit: 250)
      rows = JSON.parse(fetch("#{ARCHIVE_INDEX}?#{query}"))
      return [] if rows == []
      raise Unavailable, "Unrecognized HTR archive index." unless rows.is_a?(Array) && rows.first == [ "original" ]
      articles(rows.drop(1).map(&:first), election_on)
    rescue JSON::ParserError
      raise Unavailable, "Could not read the HTR archive index."
    end

    def self.articles(urls, election_on)
      urls.filter_map do |url|
        match = %r{\Ahttps?://(?:www\.)?htrnews\.com(/story/news/(?:[a-z-]+/)*(\d{4}/\d{2}/\d{2})/([a-z0-9-]+)/\d+/?)(?:\?[^#]*)?\z}.match(url)
        next unless match
        slug = match[3]
        next unless slug.include?("two-rivers") && slug.include?("council") && slug.match?(/\bcandidates?\b/)
        next unless slug.match?(/\b(?:share|priorities|issues|questionnaire|meet|talk|views|answer|answers)\b/)
        next if slug.match?(/\b(?:forum|results|winners)\b/)
        date = Date.strptime(match[2], "%Y/%m/%d")
        next unless date.between?(Date.new(election_on.year, 3, 1), election_on)
        Article.new("https://www.htrnews.com#{match[1].delete_suffix('/')}/", date)
      rescue Date::Error
        nil
      end.uniq(&:url)
    end
    private_class_method :articles

    def self.fetch(url)
      uri = URI(url)
      body = +"".b
      Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 45, max_retries: 0) do |http|
        request = Net::HTTP::Get.new(uri, "User-Agent" => "TwoRiversReporter-election-desk")
        http.request(request) do |response|
          raise Unavailable, "HTTP #{response.code} from #{uri.host}" unless response.is_a?(Net::HTTPSuccess)
          response.read_body do |chunk|
            raise Unavailable, "Response exceeded 5 MB." if body.bytesize + chunk.bytesize > 5.megabytes
            body << chunk
          end
        end
      end
      body
    rescue IOError, SystemCallError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError, Net::HTTPBadResponse
      raise Unavailable, "Could not retrieve #{uri.host}."
    end
  end
end
