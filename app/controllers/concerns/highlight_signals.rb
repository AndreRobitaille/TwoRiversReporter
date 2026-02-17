module HighlightSignals
  extend ActiveSupport::Concern

  HIGHLIGHT_WINDOW = 30.days

  HIGHLIGHT_EVENT_TYPES = %w[
    agenda_recurrence
    deferral_signal
    cross_body_progression
    disappearance_signal
    rules_engine_update
  ].freeze

  private

  def build_highlight_signals(topic_ids = nil)
    scope = TopicStatusEvent
      .where(evidence_type: HIGHLIGHT_EVENT_TYPES)
      .where(occurred_at: HIGHLIGHT_WINDOW.ago..)

    if topic_ids
      scope = scope.where(topic_id: topic_ids)
    else
      scope = scope.where(topic_id: Topic.publicly_visible.select(:id))
    end

    events = scope.select(:topic_id, :evidence_type, :lifecycle_status)

    signals = {}
    events.each do |event|
      label = helpers.highlight_signal_label(event.evidence_type, event.lifecycle_status)
      next unless label

      signals[event.topic_id] ||= []
      signals[event.topic_id] << label unless signals[event.topic_id].include?(label)
    end
    signals
  end
end
