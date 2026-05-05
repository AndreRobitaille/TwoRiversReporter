module Topics
  class RoutingService
    HAMILTON_HINTS = ["hamilton", "former hamilton", "former hamilton site"].freeze

    def self.call(name, context: {})
      new(name, context: context).call
    end

    def initialize(name, context: {})
      @name = Topic.normalize_name(name)
      @context = context || {}
    end

    def call
      exact_reusable = Topic.reusable.where("LOWER(name) = ?", @name).first
      return exact_reusable if exact_reusable

      return nil unless unsafe_redevelopment_label?

      route_to_former_hamilton_site if strong_hamilton_context?
    end

    private

    def unsafe_redevelopment_label?
      @name.in?(%w[redevelopment redevelopments redevelopment project]) || @name == "redevelopment"
    end

    def strong_hamilton_context?
      haystack = [@context[:text], @context[:body_name], @context[:meeting_body]].compact.join(" ").downcase
      HAMILTON_HINTS.any? { |hint| haystack.include?(hint) }
    end

    def route_to_former_hamilton_site
      Topic.reusable.where("LOWER(name) LIKE ?", "%former hamilton site%").first ||
        Topic.reusable.where("LOWER(name) LIKE ?", "%hamilton%").first
    end
  end
end
