module Topics
  # Stable IDs connect analysis to agenda evidence even when the model rewrites
  # a title. Older summaries can still match by an unambiguous normalized title.
  class ItemDetailsMatcher
    def initialize(agenda_items, item_details)
      @items_by_id = agenda_items.index_by(&:id)
      @item_details = Array(item_details)
      @items_by_title = Hash.new { |hash, title| hash[title] = [] }

      agenda_items.each do |item|
        [ item.title, item.display_context_title ].map { |title| TitleNormalizer.normalize(title) }.uniq.each do |title|
          @items_by_title[title] << item unless title.blank?
        end
      end
    end

    def build
      matches = Hash.new { |hash, id| hash[id] = [] }
      @item_details.each do |entry|
        next unless entry.is_a?(Hash)

        item = matching_item(entry)
        matches[item.id] << entry if item
      end

      # Conflicting entries must not silently overwrite one another.
      matches.filter_map { |id, entries| [ id, entries.first ] if entries.one? }.to_h
    end

    private

    def matching_item(entry)
      id = entry["agenda_item_id"]
      unless id.nil?
        return nil unless id.to_s.match?(/\A[1-9]\d*\z/)

        # A supplied ID must belong to this meeting. Never fall back to title
        # matching for an invalid or foreign ID.
        return @items_by_id[id.to_i]
      end

      title = entry["agenda_item_title"]
      return nil unless title.is_a?(String)

      candidates = @items_by_title[TitleNormalizer.normalize(title)]
      candidates.first if candidates.one?
    end
  end
end
