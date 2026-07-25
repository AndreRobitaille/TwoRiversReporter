module HomeHelper
  # Roughly six words. `teaser` truncates on a word boundary, so this is an
  # upper bound the cut backs off from — 38 characters lands on the sixth or
  # seventh word of a typical briefing headline. Deliberately much shorter
  # than the 90-character index-card teaser: the homepage is the one surface
  # a stranger lands on cold, and the owner asked for a taste, not a paragraph.
  GATED_CARD_HEADLINE_CHARS = 38
end
