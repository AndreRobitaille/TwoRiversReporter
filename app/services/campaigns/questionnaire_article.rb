module Campaigns
  # Read publisher markup as data. Only named Council answers enter the analysis body.
  class QuestionnaireArticle
    Result = Data.define(:body, :portraits)

    def initialize(edition, lead)
      @names = edition.fetch("candidates")
      @lead = lead
    end

    def read(html, clipboard: false)
      document = Nokogiri::HTML5(html, nil, "UTF-8")
      article = document.at_css(@lead.fetch("body_selector"))
      article ||= document.at_css("body") if clipboard
      raise ArgumentError, "Article text missing." unless article

      article.css("script, style, template, aside, nav").remove
      article.css("br").each { |br| br.replace("\n") }
      return QuestionFirstArticle.new(@names, @lead.fetch("questions")).read(article) if @lead["questions"]

      return assemble(named_profiles(article)) if @lead["named_profiles"]

      if @lead["start_heading"]
        nodes = council_nodes(article, clipboard)
        heading_tag = "h3"
      else
        nodes = article.css("h2, p, li, figure").reject { |node| node.ancestors("p, li, figure").any? }
        heading_tag = "h2"
      end
      if (ending = @lead["profiles_end_heading"])
        nodes = nodes.drop_while { |node| node.name != heading_tag }
        stop = nodes.index { |node| node.name == heading_tag && node.text.squish == ending }
        raise ArgumentError, "The end of the candidate profiles is missing." unless stop || clipboard

        nodes = nodes.take(stop) if stop
      end

      blocks = nodes.slice_before { |node| node.name == heading_tag }.to_a
      responses = blocks.select { |heading, *| heading.name == heading_tag }
      introduction = blocks.first if blocks.first&.first&.name != heading_tag
      assemble(responses, Array(introduction))
    end

    # In a plain-text copy Yahoo puts a recommendation panel between these two biographical fields.
    def self.clean_paste(body, names)
      lines = body.to_s.lines
      start = lines.index { |line| line.strip == "More to explore" }
      if start && lines.take(start).reject(&:blank?).last.to_s.start_with?("Highest education level:")
        finish = lines.each_index.find { |i| i > start && lines[i].start_with?("Political or elected official experience:") }
        if finish && lines[start...finish].none? { |line| names.include?(line.strip) || line.strip.end_with?("?") }
          lines.slice!(start...finish)
        end
      end
      previous = nil
      lines.reject do |line|
        heading = line.strip
        repeated = names.include?(heading) && previous == heading
        previous = heading if heading.present?
        repeated
      end.join
    end

    private

    def named_profiles(article)
      nodes = article.css("h2, h3, p, li, figure").reject { |node| node.ancestors("p, li, figure").any? }
      council = nodes.index { |node| node.name == "h2" && node.text.squish.casecmp?("Two Rivers City Council") }
      if council
        nodes = nodes.drop(council + 1).take_while { |node| node.name != "h2" }
      elsif @names.empty?
        raise ArgumentError, "Supply the named Council answers or add the candidate list."
      end

      nodes.slice_before { |node| %w[h2 h3].include?(node.name) }.select do |heading, *|
        %w[h2 h3].include?(heading.name) && (council || @names.include?(heading.text.squish))
      end
    end

    def assemble(responses, introduction = [])
      names = responses.map { |heading, *| heading.text.squish }
      if names.empty? || names.uniq != names || (@names.any? && names.sort != @names.sort)
        raise ArgumentError, "The candidate headings do not match this Council race."
      end

      portraits = {}
      body = text_lines(introduction)
      responses.each do |heading, *answer|
        name = heading.text.squish
        lines = text_lines(answer)
        raise ArgumentError, "Check the response for #{name}." unless answered?(lines.map(&:squish))

        body.push(heading.text.strip, *lines)
        photo = portrait(answer, name)
        portraits[name] = photo if photo
      end
      Result.new(body.join("\n\n"), portraits)
    end

    def text_lines(nodes)
      lines = nodes.reject { |node| node.name == "figure" }.map { |node| node.text.strip }.compact_blank
      return lines unless @lead["profiles_end_heading"]

      question = @lead.fetch("response_question")
      lines.flat_map do |line|
        line.start_with?(question) ? [ question, line.delete_prefix(question).strip ].compact_blank : line
      end
    end

    def portrait(nodes, name)
      format = if @lead["profiles_end_heading"] || @lead["named_profiles"]
        :gannett
      elsif @lead["start_heading"]
        :yahoo
      else
        :seehafer
      end
      title = @lead.fetch("headshot_titles", {}).fetch(name, "#{name} headshot")
      ArticlePortraits.find_image(nodes, name, format, title: title)
    end

    def council_nodes(article, clipboard)
      first = article.css("h2").find { |node| node.text.squish == @lead.fetch("start_heading") }
      if first
        siblings = first.xpath("following-sibling::*").to_a
        finish = siblings.index { |node| node.name == "h2" && node.text.squish == @lead.fetch("end_heading") }
        raise ArgumentError, "The end of the Council section is missing." unless finish || clipboard
        siblings = siblings.take(finish) if finish
      elsif clipboard && (heading = article.css("h3").find { |node| @names.include?(node.text.squish) })
        siblings = [ heading, *heading.xpath("following-sibling::*") ].take_while { |node| node.name != "h2" }
      else
        raise ArgumentError, "The Council section heading is missing."
      end

      siblings.flat_map do |node|
        case node.name
        when "ul", "ol" then node.xpath("./li").to_a
        when "p", "h3", "figure" then [ node ]
        else []
        end
      end.reject { |node| node.text.squish == "Advertisement" }
    end

    def answered?(lines)
      if @lead["named_profiles"]
        return true if lines == [ "Did not answer." ]
        return lines.join(" ").match?(/\?\s*\S/)
      end
      question = @lead["response_question"]
      return lines.any? unless question
      return true if lines == [ "Did not answer." ]

      index = lines.index(question)
      index && index < lines.size - 1
    end
  end
end
