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

    visible = text.to_s.truncate(chars, separator: " ", omission: "")
    modifier = fade == :inline ? " teaser-fade--inline" : ""

    tag.span(visible, class: "teaser-fade#{modifier}")
  end
end
