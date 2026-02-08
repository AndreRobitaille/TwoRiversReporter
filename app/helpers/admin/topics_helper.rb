module Admin::TopicsHelper
  DEFAULT_PREVIEW_WINDOW = 160
  MAX_PREVIEW_WINDOW = 400

  def topic_recent_mentions(topic, limit: 3)
    topic.agenda_items
         .includes(:meeting_documents, meeting: { meeting_documents: :extractions })
         .order("meetings.starts_at DESC")
         .limit(limit)
  end

  def topic_mention_preview(agenda_item, topic, window: DEFAULT_PREVIEW_WINDOW)
    preview_terms = topic_preview_terms(topic)
    return nil if preview_terms.empty?

    # Try specific documents linked to agenda item first
    documents = agenda_item.meeting_documents
    # Fallback to meeting documents if no specific agenda documents
    documents = agenda_item.meeting.meeting_documents if documents.empty?

    documents.each do |document|
      preview = preview_from_document(document, preview_terms, window)
      return preview if preview
    end

    nil
  end

  def preview_window_from_params(params, default: DEFAULT_PREVIEW_WINDOW)
    window = params[:preview_window].to_i
    return default if window <= 0

    [ window, MAX_PREVIEW_WINDOW ].min
  end

  private

  def topic_preview_terms(topic)
    ([ topic.name ] + topic.topic_aliases.map(&:name)).compact.uniq
  end

  def preview_from_document(document, terms, window)
    extractions = document.extractions
    extractions = extractions.order(:page_number) unless extractions.loaded?

    extractions.each do |extraction|
      text = extraction.cleaned_text.presence || extraction.raw_text
      next if text.blank?

      preview = preview_from_text(text, terms, window)
      if preview
        preview[:page_number] = extraction.page_number
        preview[:document_type] = document.document_type
        return preview
      end
    end

    return nil if document.extracted_text.blank?

    preview = preview_from_text(document.extracted_text, terms, window)
    return nil unless preview

    preview[:document_type] = document.document_type
    preview
  end

  def preview_from_text(text, terms, window)
    regex = Regexp.union(terms.map { |term| Regexp.new(Regexp.escape(term), Regexp::IGNORECASE) })
    match = regex.match(text)
    return nil unless match

    start_index = [ match.begin(0) - window, 0 ].max
    end_index = [ match.end(0) + window, text.length ].min
    excerpt = text[start_index...end_index].to_s.strip.gsub(/\s+/, " ")
    prefix = start_index.positive? ? "..." : ""
    suffix = end_index < text.length ? "..." : ""

    { text: "#{prefix}#{excerpt}#{suffix}", terms: terms }
  end

  def highlight_preview_terms(text, terms)
    regex = Regexp.union(terms.map { |term| Regexp.new(Regexp.escape(term), Regexp::IGNORECASE) })
    highlighted = text.gsub(regex) do |match|
      "<span class=\"font-bold italic bg-yellow-100 dark:bg-yellow-900 px-1 rounded-sm\">#{match}</span>"
    end
    sanitize(highlighted, tags: %w[span], attributes: %w[class])
  end
end
