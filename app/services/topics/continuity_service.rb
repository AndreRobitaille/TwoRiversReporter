module Topics
  class ContinuityService
    # Constants
    ACTIVITY_WINDOW = 6.months
    DISAPPEARANCE_WINDOW = 12.months
    RESOLUTION_COOLDOWN = 6.months

    RESOLVED_OUTCOMES = %w[
      passed
      adopted
      approved
      accepted
      enacted
      carried
    ].freeze

    DEFERRAL_KEYWORDS = %w[
      defer
      continue
      table
      postpone
      lay\ over
    ].freeze

    def self.call(topic)
      new(topic).call
    end

    def initialize(topic)
      @topic = topic
    end

    def call
      load_context
      derive_lifecycle_status
      detect_signals
      persist_results
    end

    private

    def load_context
      @appearances = @topic.topic_appearances.order(:appeared_at)
      @latest_appearance = @appearances.last

      # Load motions linked via agenda items
      # This assumes motions are correctly linked to agenda items
      @resolved_motions = Motion.joins(:agenda_item)
                                .where(agenda_items: { id: @topic.agenda_items.select(:id) })
                                .where("LOWER(outcome) IN (?)", RESOLVED_OUTCOMES)
                                .includes(:meeting)
                                .order("meetings.starts_at ASC")

      @latest_resolved_motion = @resolved_motions.last
    end

    def derive_lifecycle_status
      @new_status = "dormant" # Default

      return unless @latest_appearance

      last_seen = @latest_appearance.appeared_at
      resolution_date = @latest_resolved_motion&.meeting&.starts_at

      if resolution_date && resolution_date.to_date >= last_seen.to_date
        # Resolution is the most recent event (or same day)
        @new_status = "resolved"
      elsif resolution_date && last_seen > (resolution_date + RESOLUTION_COOLDOWN)
        # Reappeared significantly after resolution
        @new_status = "recurring"
      elsif last_seen > ACTIVITY_WINDOW.ago
        # Recent activity, no dominating resolution
        @new_status = "active"
      else
        # No recent activity
        @new_status = "dormant"
      end
    end

    def detect_signals
      @events_to_log = []

      # 0. Ensure all resolved motions have corresponding events (Historical backfill)
      @resolved_motions.each do |motion|
         add_event(
           lifecycle_status: "resolved",
           evidence_type: "motion_outcome",
           occurred_at: motion.meeting.starts_at,
           source_ref: {
             motion_id: motion.id,
             outcome: motion.outcome
           }
         )
      end

      # 1. Resolution Event (Current Status)
      # Handled by step 0 technically, but kept for clarity if logic diverges

      # 2. Recurring Event
      if @new_status == "recurring" && @latest_resolved_motion
         add_event(
           lifecycle_status: "recurring",
           evidence_type: "agenda_recurrence",
           occurred_at: @latest_appearance.appeared_at,
           source_ref: {
             prior_resolution_date: @latest_resolved_motion.meeting.starts_at
           }
         )
      end

      # 3. Deferral Signals
      # Check the latest appearance for deferral language
      if @latest_appearance&.agenda_item
        ai = @latest_appearance.agenda_item
        text = [ ai.title, ai.recommended_action, ai.summary ].compact.join(" ").downcase

        matched_kw = DEFERRAL_KEYWORDS.find { |kw| text.include?(kw) }
        if matched_kw
          add_event(
            lifecycle_status: @new_status,
            evidence_type: "deferral_signal",
            occurred_at: @latest_appearance.appeared_at,
            source_ref: {
              keyword: matched_kw,
              agenda_item_id: ai.id
            },
            notes: "Matched deferral keyword: #{matched_kw}"
          )
        end
      end

      # 4. Disappearance Signal
      # If strictly dormant (not resolved) and huge gap since last appearance
      if @new_status == "dormant" &&
         @latest_appearance &&
         @latest_appearance.appeared_at < DISAPPEARANCE_WINDOW.ago &&
         !@resolved_motions.any? # Not resolved, just vanished

         # Only log if we haven't already
         add_event(
           lifecycle_status: "dormant",
           evidence_type: "disappearance_signal",
           occurred_at: @latest_appearance.appeared_at + DISAPPEARANCE_WINDOW,
           source_ref: {
             last_seen: @latest_appearance.appeared_at
           },
           notes: "No activity for over 12 months"
         )
      end

      # 5. Cross-body Progression
      # Scan appearances for body changes
      current_body = nil
      @appearances.each do |app|
        next if app.body_name.blank?

        if current_body && app.body_name != current_body
           add_event(
             lifecycle_status: @new_status, # This signal doesn't dictate status
             evidence_type: "cross_body_progression",
             occurred_at: app.appeared_at,
             source_ref: {
               from: current_body,
               to: app.body_name,
               appearance_id: app.id
             }
           )
        end
        current_body = app.body_name
      end
    end

    def add_event(attrs)
      @events_to_log << attrs
    end

    def persist_results
      ActiveRecord::Base.transaction do
        # Update Topic Status
        if @topic.lifecycle_status != @new_status
          @topic.update!(lifecycle_status: @new_status)

          # Log the transition itself if not covered by specific events
          # This ensures we always know WHY status changed
          unless @events_to_log.any? { |e| e[:lifecycle_status] == @new_status && e[:evidence_type] != "cross_body_progression" && e[:evidence_type] != "deferral_signal" }
            TopicStatusEvent.create!(
              topic: @topic,
              lifecycle_status: @new_status,
              evidence_type: "rules_engine_update",
              occurred_at: Time.current,
              notes: "Derived from continuity rules"
            )
          end
        end

        # Create Events (Idempotent)
        @events_to_log.each do |attrs|
          # Use a loose uniqueness check: same topic, type, date, and status
          # We don't want to spam events every time the job runs

          # For signals like deferral, we might have multiple on same day? Unlikely for same topic.

          unless TopicStatusEvent.where(
            topic: @topic,
            evidence_type: attrs[:evidence_type],
            lifecycle_status: attrs[:lifecycle_status],
            occurred_at: attrs[:occurred_at]
          ).exists?
            TopicStatusEvent.create!(attrs.merge(topic: @topic))
          end
        end

        # Update First/Last Seen
        updates = {}
        if @appearances.any?
          first = @appearances.first.appeared_at
          last = @appearances.last.appeared_at

          updates[:first_seen_at] = first if @topic.first_seen_at != first
          updates[:last_seen_at] = last if @topic.last_seen_at != last
          updates[:last_activity_at] = last if @topic.last_activity_at.nil? || @topic.last_activity_at < last
        end

        @topic.update!(updates) if updates.any?
      end
    end
  end
end
