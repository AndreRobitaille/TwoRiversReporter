module ResidentContent
  # Filters saved votes before pagination. Topic joins never multiply decisions,
  # and the existing featured/procedural rule stays the same in both views.
  class VoteFilters
    attr_reader :topics, :bodies, :query_params

    def initialize(profile, params:)
      @profile = profile
      @records = profile.votes.to_a
      @topics = @records.flat_map { |vote| topics_for(vote).select(&:approved?) }
        .uniq(&:id).sort_by(&:canonical_name)
      @bodies = @records.map { |vote| vote.motion.meeting.body_name }.compact.uniq.sort
      choices = { topic: topics.map { |topic| topic.id.to_s }, body: bodies,
        kind: %w[substantive procedural], split: %w[divided] }
      @query_params = choices.filter_map do |key, allowed|
        [ key, params[key] ] if params[key].is_a?(String) && allowed.include?(params[key])
      end.to_h
      query = params[:q].is_a?(String) ? params[:q].strip.first(200) : ""
      @query_params[:q] = query if query.present?
    end

    def active?
      query_params.any?
    end

    def call(featured:)
      words = query_params.fetch(:q, "").downcase.split
      @records.select do |vote|
        motion = vote.motion
        next false if featured && !@profile.featured_vote?(vote)
        next false if query_params[:body] && motion.meeting.body_name != query_params[:body]
        next false if query_params[:topic] && !topics_for(vote).any? { |topic| topic.id.to_s == query_params[:topic] && topic.approved? }
        next false if query_params[:kind] == "substantive" && !@profile.substantive_motion?(motion)
        next false if query_params[:kind] == "procedural" && @profile.substantive_motion?(motion)
        if query_params[:split] == "divided"
          values = motion.votes.map(&:value)
          next false unless values.include?("yes") && values.include?("no")
        end
        next true if words.empty?

        text = [ motion.description, motion.agenda_item&.display_context_title ].compact.join(" ").downcase
        words.all? { |word| text.include?(word) }
      end
    end

    private

    def topics_for(vote)
      vote.motion.agenda_item&.agenda_item_topics&.map(&:topic) || []
    end
  end
end
