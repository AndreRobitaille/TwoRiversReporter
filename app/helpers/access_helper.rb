module AccessHelper
  # Renders as much of `text` as an anonymous visitor is allowed to see.
  #
  # The withheld remainder is never placed in the response — the fade is a
  # visual disguise for the truncation point, not a concealment mechanism.
  #
  # fade: :block  — vertical gradient, for multi-line prose
  # fade: :inline — horizontal gradient, for single-line card headlines
  def teaser(text, chars:, fade: :block)
    return nil if text.blank?
    return text unless gated_for_visitor?

    # Force a plain String before truncating: when no truncation actually
    # fires, String#truncate returns `dup` of the input, and `dup` on an
    # ActiveSupport::SafeBuffer preserves html_safe — which would make
    # tag.span skip escaping. String.new(...) strips that flag.
    visible = String.new(text.to_s).truncate(chars, separator: " ", omission: "")
    modifier = fade == :inline ? " teaser-fade--inline" : ""

    tag.span(visible, class: "teaser-fade#{modifier}")
  end

  # ==========================================================================
  # Gated skeleton geometry
  # ==========================================================================
  #
  # Below the gate we render grey placeholder bars whose *shape* mirrors the
  # withheld prose, so a visitor can see how much there is to read without
  # reading any of it. That shape is a side channel, and this branch has
  # already shipped one leak whose response body contained no withheld bytes
  # but whose geometry was a function of them. So every measurement derived
  # from real text is quantized before it reaches the DOM:
  #
  #   length -> one of four buckets (LENGTH_BUCKET_BOUNDS). A 130-character
  #             item and a 310-character item produce byte-identical markup.
  #
  #   lines  -> LINES_PER_BUCKET, hard-capped at 4. Everything past the last
  #             bound renders the same, so "long" and "enormous" are
  #             indistinguishable.
  #
  #   widths -> picked from a fixed pattern table by (item index + length
  #             bucket + line number). Deterministic for a given item, so the
  #             page does not reflow between loads, but carries no
  #             per-character information at all. Never derive a width from a
  #             word length, a character count, or a hash of the text: a
  #             sequence of word lengths identifies the text that produced it.
  #
  # The only real information the skeleton exposes is the item count per
  # section, which is volume information the owner wants and which the
  # meeting's existence already implies.
  #
  # Do not "improve" the fidelity of these bars. Fidelity is the channel.

  # Prose bodies: highlight text, public-input summaries, agenda item summaries.
  LENGTH_BUCKET_BOUNDS = [ 120, 320, 700 ].freeze
  LINES_PER_BUCKET = [ 1, 2, 3, 4 ].freeze

  # Titles are much shorter than bodies, so they get their own coarse bounds
  # rather than collapsing every title into bucket 0.
  TITLE_BUCKET_BOUNDS = [ 30, 55, 85 ].freeze
  TITLE_WIDTHS = %w[m l xl full].freeze

  # Each entry is one rendered line, as a list of bar widths. Interior lines
  # fill most of the measure; the tail line is short so the block reads as a
  # paragraph that stops mid-line.
  BODY_LINE_PATTERNS = [
    %w[xl m],
    %w[l l],
    %w[m xl],
    %w[m m m],
    %w[s l m],
    %w[l s m]
  ].freeze

  TAIL_LINE_PATTERNS = [
    %w[m],
    %w[l],
    %w[xl],
    %w[s m],
    %w[m m]
  ].freeze

  def skeleton_length_bucket(text, bounds: LENGTH_BUCKET_BOUNDS)
    length = text.to_s.length
    bounds.index { |bound| length <= bound } || bounds.size
  end

  # Returns the per-line bar-width plan for one item: an array of arrays of
  # width keys. Quantized as described above.
  def skeleton_lines(text, index:)
    bucket = skeleton_length_bucket(text)
    count = LINES_PER_BUCKET[bucket]
    seed = index + bucket

    Array.new(count) do |line|
      table = line == count - 1 ? TAIL_LINE_PATTERNS : BODY_LINE_PATTERNS
      table[(seed + line) % table.size]
    end
  end

  # Renders the bars for one item. Decorative only — the caller marks the
  # wrapper aria-hidden and supplies a real screen-reader line beside it.
  def skeleton_bars(text, index:)
    safe_join(skeleton_lines(text, index: index).map do |segments|
      tag.div(class: "gated-skeleton__line") do
        safe_join(segments.map { |width| tag.span(nil, class: "gated-skeleton__bar gated-skeleton__bar--#{width}") })
      end
    end)
  end

  # A single heavier bar standing in for an item title.
  def skeleton_title_bar(text)
    width = TITLE_WIDTHS[skeleton_length_bucket(text, bounds: TITLE_BUCKET_BOUNDS)]
    tag.span(nil, class: "gated-skeleton__bar gated-skeleton__bar--title gated-skeleton__bar--#{width}")
  end
end
