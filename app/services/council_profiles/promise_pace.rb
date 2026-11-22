module CouncilProfiles
  # Equal progress over the scheduled term is a comparison, not a project deadline.
  class PromisePace
    LABELS = { "green" => "At or ahead of an even pace", "amber" => "Just behind an even pace", "red" => "Behind an even pace" }.freeze

    attr_reader :ends_on, :days_left

    def initialize(score, started_on:, ends_on:, as_of: Date.current)
      @score = score
      return unless ends_on && started_on && ends_on > started_on && as_of >= started_on

      @ends_on = ends_on
      @days_left = [ (ends_on - as_of).to_i, 0 ].max
      @elapsed = 1 - @days_left / (ends_on - started_on)
    end

    def elapsed_percent
      (100 * @elapsed).round if @elapsed
    end

    def rating
      return unless @elapsed && @score.total.positive?

      gap = @elapsed - Rational(@score.net_points, @score.total)
      return "green" if gap <= 0
      return "red" if days_left.zero? || gap > Rational(1, 10)

      "amber"
    end

    def label
      return unless rating
      return @score.met == @score.total ? "All promises credited" : "Term ended short" if days_left.zero?

      LABELS.fetch(rating)
    end
  end
end
