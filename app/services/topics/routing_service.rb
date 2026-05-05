module Topics
  class RoutingService
    def self.call(name, item_title: nil, item_summary: nil, meeting_body_name: nil, document_text: nil, existing_topics: nil)
      new(
        name,
        item_title: item_title,
        item_summary: item_summary,
        meeting_body_name: meeting_body_name,
        document_text: document_text,
        existing_topics: existing_topics
      ).call
    end

    def initialize(name, item_title: nil, item_summary: nil, meeting_body_name: nil, document_text: nil, existing_topics: nil)
      @name = Topic.normalize_name(name)
      @item_title = item_title
      @item_summary = item_summary
      @meeting_body_name = meeting_body_name
      @document_text = document_text
      @existing_topics = Array(existing_topics)
    end

    def call
      exact_topic = Topic.reusable.where("LOWER(name) = ?", @name).first
      return exact_topic if exact_topic

      exact_alias = TopicAlias.joins(:topic).merge(Topic.reusable).where("LOWER(topic_aliases.name) = ?", @name).first
      return exact_alias.topic if exact_alias

      return nil unless unsafe_redevelopment_label?

      route_to_former_hamilton_site if strong_hamilton_context?
    end

    private

    def unsafe_redevelopment_label?
      @name.in?(%w[redevelopment redevelopments])
    end

    def strong_hamilton_context?
      text = [ @item_title, @item_summary, @meeting_body_name, @document_text ].compact.join(" ").downcase
      signals = [
        text.include?("former hamilton site"),
        text.include?("former hamilton property"),
        text.include?("hamilton property"),
        text.include?("hamilton site"),
        text.include?("parcel"),
        text.include?("fischer"),
        text.include?("visioning"),
        text.include?("former hamilton")
      ]

      signals.count(true) >= 2
    end

    def route_to_former_hamilton_site
      Topic.reusable.where("LOWER(name) = ?", "former hamilton site").first
    end
  end
end
