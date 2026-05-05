module Topics
  class RoutingService
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
      @name.in?(%w[redevelopment redevelopments])
    end

    def strong_hamilton_context?
      haystack = [@context[:text], @context[:body_name], @context[:meeting_body]].compact.join(" ").downcase
      haystack.include?("former hamilton site")
    end

    def route_to_former_hamilton_site
      Topic.reusable.where("LOWER(name) = ?", "former hamilton site").first
    end
  end
end
