module Campaigns
  # HTR prints biographies by candidate, then asks the whole field each question.
  class QuestionFirstArticle
    def initialize(names, questions)
      @names = names
      @questions = questions
      @surnames = names.index_by { |name| name.split.last }
    end

    def read(article)
      article.css("p:has(.gnt_ar_b_al), p:has(em:first-child):has(a[href*='mailto:'])").remove
      blocks = article.css("h2, p, figure").reject { |node| node.ancestors("p, figure").any? }
        .slice_before { |node| node.name == "h2" }.to_a
      intro = blocks.shift if blocks.first&.first&.name != "h2"
      headings = blocks.map { |heading, *| heading.text.squish }
      unless headings.take(@names.size).sort == @names.sort && headings.drop(@names.size) == @questions
        raise ArgumentError, "The candidate biographies or published questions are incomplete."
      end

      candidates = {}
      portraits = {}
      blocks.shift(@names.size).each do |heading, *bio|
        name = heading.text.squish
        biography = bio.select { |node| node.name == "p" }.map { |node| node.text.squish }.compact_blank
        raise ArgumentError, "The biography for #{name} is missing." if biography.empty?

        candidates[name] = [ name, *biography ]
        photo = ArticlePortraits.find_image(bio, name, :gannett)
        portraits[name] = photo if photo
      end
      blocks.each do |question, *responses|
        copy_responses(candidates, question.text.squish, responses)
      end

      introduction = Array(intro).select { |node| node.name == "p" }.map { |node| node.text.squish }
      QuestionnaireArticle::Result.new((introduction + candidates.values.flatten).join("\n\n"), portraits)
    end

    private

    def copy_responses(candidates, question, responses)
      seen = []
      responses.select { |node| node.name == "p" }.each do |node|
        text = node.text.squish
        label = node.at_css("strong, b")&.text&.squish&.delete_suffix(":")
        if label && (name = @surnames[label]) && text.start_with?("#{label}:")
          answer = text.delete_prefix("#{label}:").strip
          raise ArgumentError, "The answer from #{name} is empty." if answer.empty?

          seen << name
          candidates.fetch(name).push(question, answer)
        elsif seen.any? && label.nil?
          candidates.fetch(seen.last) << text
        else
          raise ArgumentError, "Check the candidate labels under “#{question}”."
        end
      end
      raise ArgumentError, "Each candidate needs an answer under “#{question}”." unless seen.sort == @names.sort
    end
  end
end
