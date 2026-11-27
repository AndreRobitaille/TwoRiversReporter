module Campaigns
  # A future article can supply photos even before its questions are cataloged.
  # Only consider headings the editor included as names in the saved Council text.
  class ArticlePortraits
    def self.read(source, html)
      source_uri = URI.parse(source.source_url.to_s)
      host = source_uri.host.to_s.delete_prefix("www.")
      document = Nokogiri::HTML5(html, nil, "UTF-8")
      selector, format = case host
      when "htrnews.com" then [ "article .gnt_ar_b", :gannett ]
      when "seehafernews.com" then [ "article .entry-content", :seehafer ]
      when "yahoo.com" then [ "article", :yahoo ] if ElectionBackfill.htr?(source)
      end
      article = document.at_css(selector) if selector
      raise ArgumentError, "Choose a saved HTR or Seehafer article with named candidate photos." unless article
      locations = [ document.at_css('link[rel="canonical"]')&.[]("href"), document.at_css('meta[property="og:url"]')&.[]("content") ].compact_blank
      if locations.any? && locations.none? { |url| article_key(URI.join(source_uri, url)) == article_key(source_uri) }
        raise ArgumentError, "The saved article identifies a different publisher link. Check the link and HTML file."
      end
      article.css("aside, nav, script, style").remove
      names = source.body.to_s.lines.map(&:squish).to_set
      portraits = {}
      article.css("h2, h3, figure").slice_before { |node| node.name != "figure" }.each do |heading, *figures|
        name = heading.text.squish
        next unless heading.name != "figure" && names.include?(name)
        url = find_image(figures, name, format)
        portraits[name] = url if url
      end
      raise ArgumentError, "No named photos matched. Put each candidate’s full name on its own line in the Council answers, or save without the HTML file." if portraits.empty?
      portraits
    rescue URI::InvalidURIError
      raise ArgumentError, "Enter the publisher link for the saved article."
    end

    def self.find_image(nodes, name, format, title: "#{name} headshot")
      return gannett_portrait(nodes, name) if format == :gannett

      nodes.each do |figure|
        next unless figure.name == "figure" && (photo = figure.at_css("img"))
        if format == :yahoo
          next unless figure.at_css("figcaption")&.text&.squish == name && photo["alt"].to_s.squish == name
          url = yahoo_image_url(photo)
        else
          url = seehafer_image_url(photo, title)
        end
        return url if url
      end
      nil
    end

    def self.article_key(uri)
      [ uri.host.to_s.delete_prefix("www."), uri.path.to_s.delete_suffix("/") ]
    end

    def self.gannett_portrait(nodes, name)
      figure = nodes.find { |node| node.name == "figure" && node.at_css("[data-c-caption]")&.[]("data-c-caption") == name }
      photo = figure&.at_css("img")
      return unless photo && photo["alt"].to_s.squish == name

      # Gannett's lazy-image path points to the original publisher image.
      path = (photo["data-gl-src"].presence || photo["src"]).to_s.split("?").first.to_s.delete_prefix("https://www.htrnews.com")
      if path.match?(%r{\A/gcdn/(?:authoring/authoring-images|presto)/\d{4}/\d{2}/\d{2}/[A-Z]+/[\w.-]+\.(?:jpe?g|png)\z}i)
        "https://www.gannett-cdn.com#{path.delete_prefix('/gcdn')}"
      end
    end

    def self.yahoo_image_url(photo)
      url = photo["src"].to_s
      # Yahoo's resized URL embeds the original publisher image.
      url = URI::DEFAULT_PARSER.unescape(url.split("/").last.to_s) if url.start_with?("https://s.yimg.com/lo/mysterio/")
      url if url.match?(%r{\Ahttps://media\.zenfs\.com/en/herald-times-reporter/[0-9a-f]{32}\z})
    end

    def self.seehafer_image_url(photo, title)
      return unless photo["title"].to_s.parameterize == title.parameterize
      url = photo["src"].to_s
      url if url.match?(%r{\Ahttps://media-cdn\.socastsrm\.com/wordpress/wp-content/blogs\.dir/1960/files/\d{4}/\d{2}/[\w-]+\.(?:png|jpe?g)\z}i)
    end

    private_class_method :article_key, :gannett_portrait, :yahoo_image_url, :seehafer_image_url
  end
end
