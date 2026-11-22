require "digest"

module CouncilProfiles
  # Restore only verified PDF footer numbers omitted by a provider. The returned
  # quotation is still a contiguous passage of the original retained source.
  class SourceQuote
    def initialize(context, document: nil)
      @context, @document = context, document
      @text = normalize(context.fetch("text"))
    end

    def resolve(quote)
      quote = normalize(quote)
      return quote if @text.include?(quote)

      text, offsets = without_footers
      start = text.index(quote)
      return unless start

      @text[offsets.fetch(start)..offsets.fetch(start + quote.length - 1)]
    end

    private

    def without_footers
      return @without_footers if @without_footers

      pages = verified_pages
      removals = []
      offset = 0
      pages.each_with_index do |page, index|
        text = normalize(page.cleaned_text)
        footer = page.page_number.to_s
        if index < pages.size - 1 && page.raw_text.to_s.lines.map(&:strip).reject(&:empty?).last == footer &&
            normalize(page.raw_text) == text && text.end_with?(" #{footer}")
          # Include the joining space after this footer; keep the space before it.
          start = offset + text.length - footer.length
          removals << (start...(start + footer.length + 1))
        end
        offset += text.length + 1
      end
      return @without_footers = [ "", [] ] if removals.empty?

      text = +""
      offsets = []
      @text.each_char.with_index do |character, index|
        next if removals.any? { |range| range.cover?(index) }

        text << character
        offsets << index
      end
      @without_footers = [ text, offsets ]
    end

    def verified_pages
      return [] unless @document && @context.dig("source", "document_id") == @document.id

      saved = @context.dig("source", "pages") || []
      pages = @document.extractions.order(:page_number, :id).to_a
      return [] unless saved.any? && pages.map(&:page_number) == (1..@document.page_count.to_i).to_a &&
        pages.size == saved.size && normalize(pages.map(&:cleaned_text).join(" ")) == @text
      return [] unless pages.zip(saved).all? do |page, snapshot|
        snapshot["page_number"] == page.page_number &&
          snapshot["text_sha256"] == Digest::SHA256.hexdigest(page.cleaned_text)
      end

      pages
    end

    def normalize(text)
      text.to_s.split.join(" ")
    end
  end
end
