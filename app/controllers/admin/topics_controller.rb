module Admin
  class TopicsController < BaseController
    before_action :set_topic, only: %i[show update approve block unblock needs_review pin unpin merge create_alias]

    def index
      @preview_window = helpers.preview_window_from_params(params)

      if params[:view] == "ai_decisions"
        @ai_events = TopicReviewEvent.automated
                                     .recent
                                     .includes(:topic)
                                     .order(created_at: :desc)
        return render :index
      end

      @topics = Topic.all

      if params[:status].present?
        @topics = @topics.where(status: params[:status])
      end

      if params[:review_status].present?
        @topics = @topics.where(review_status: params[:review_status])
      end

      if params[:pinned] == "true"
        @topics = @topics.pinned
      end

      if params[:q].present?
        @topics = @topics.similar_to(params[:q])
      else
        @topics = sort_topics(@topics)
      end

      # Simple pagination
      @page = [ params[:page].to_i, 1 ].max
      @per_page = 50

      # execute count before limit/offset
      # Use .size which handles grouped queries correctly (returning a hash) or integer for standard queries
      count_result = @topics.size
      @total_topics = count_result.is_a?(Hash) ? count_result.size : count_result
      @total_pages = (@total_topics.to_f / @per_page).ceil

      @topics = @topics.offset((@page - 1) * @per_page).limit(@per_page)
    end

    def search
      @topics = Topic.where("name ILIKE ?", "%#{params[:q]}%").limit(20)
      render json: @topics.select(:id, :name)
    end

    def show
      @aliases = @topic.topic_aliases
      @preview_window = helpers.preview_window_from_params(params)
      @recent_mentions = @topic.agenda_items.includes(meeting: { meeting_documents: :extractions })
        .order("meetings.starts_at DESC")
        .limit(10)
    end

    def update
      @topic.assign_attributes(topic_params)

      if @topic.will_save_change_to_attribute?(:description)
        @topic.description_generated_at = nil
      end

      if @topic.source_notes_changed?
        if @topic.source_notes.present?
          @topic.added_by = Current.user&.email
          @topic.added_at = Time.current
        else
          @topic.added_by = nil
          @topic.added_at = nil
        end
      end

      if @topic.will_save_change_to_attribute?(:resident_impact_score) && @topic.resident_impact_score.present?
        @topic.resident_impact_overridden_at = Time.current
      end

      if @topic.save
        respond_to do |format|
          format.html { redirect_back fallback_location: admin_topics_path, notice: "Topic updated." }
          format.turbo_stream { render_turbo_update("Topic updated.") }
          format.json { render json: { success: true } }
        end
      else
        respond_to do |format|
          format.html { render :show, status: :unprocessable_entity }
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@topic),
            partial: "admin/topics/topic",
            locals: { topic: @topic, preview_window: helpers.preview_window_from_params(params) }
          )
        }
          format.json { render json: { success: false, errors: @topic.errors.full_messages }, status: :unprocessable_entity }
        end
      end
    end

    def approve
      @topic.update(status: "approved", review_status: "approved")
      record_review_event(@topic, "approved")
      render_turbo_update("Topic approved.")
    end

    def block
      @topic.update(status: "blocked", review_status: "blocked")
      record_review_event(@topic, "blocked")
      expand_blocklist(@topic.name)
      render_turbo_update("Topic blocked.")
    end

    def unblock
      # Default to approved as that is now the standard state
      @topic.update(status: "approved", review_status: "approved")
      record_review_event(@topic, "unblocked")
      render_turbo_update("Topic unblocked.")
    end

    def needs_review
      @topic.update(status: "proposed", review_status: "proposed")
      record_review_event(@topic, "needs_review")
      render_turbo_update("Topic moved to review queue.")
    end

    def pin
      @topic.update(pinned: true)
      render_turbo_update("Topic pinned.")
    end

    def unpin
      @topic.update(pinned: false)
      render_turbo_update("Topic unpinned.")
    end

    def merge
      target_topic = Topic.find(params[:target_topic_id])

      ActiveRecord::Base.transaction do
        # Create alias from the merged topic name
        TopicAlias.create!(topic: target_topic, name: @topic.name)

        # Move aliases
        @topic.topic_aliases.update_all(topic_id: target_topic.id)

        # Move agenda items
        @topic.agenda_item_topics.each do |ait|
          # Only create if not exists
          unless AgendaItemTopic.exists?(agenda_item: ait.agenda_item, topic: target_topic)
            ait.update!(topic: target_topic)
          else
            ait.destroy # Duplicate link
          end
        end

        # Delete source topic
        @topic.destroy!
      end

      redirect_to admin_topic_path(target_topic), notice: "Topic merged successfully."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_topic_path(@topic), alert: "Target topic not found."
    rescue => e
      redirect_to admin_topic_path(@topic), alert: "Merge failed: #{e.message}"
    end

    def create_alias
      @alias = @topic.topic_aliases.build(name: params[:name])

      if @alias.save
        redirect_to admin_topic_path(@topic), notice: "Alias added."
      else
        redirect_to admin_topic_path(@topic), alert: "Failed to add alias: #{@alias.errors.full_messages.join(', ')}"
      end
    end

    def search
      topics = Topic.where("name ILIKE ?", "%#{params[:q]}%").limit(20)
      render json: topics.select(:id, :name)
    end

    def bulk_update
      if params[:topic_ids].blank?
        redirect_back fallback_location: admin_topics_path, alert: "No topics selected."
        return
      end

      topic_ids = Array(params[:topic_ids])
      topics = Topic.where(id: topic_ids)
      reason = params[:reason].presence

      notice = case params[:commit]
      when "Approve Selected"
        topics.update_all(status: "approved", review_status: "approved")
        record_bulk_review_events(topic_ids, "approved", reason)
        "Selected topics approved."
      when "Block Selected"
        topics.update_all(status: "blocked", review_status: "blocked")
        record_bulk_review_events(topic_ids, "blocked", reason)
        "Selected topics blocked."
      when "Mark for Review"
        topics.update_all(status: "proposed", review_status: "proposed")
        record_bulk_review_events(topic_ids, "needs_review", reason)
        "Selected topics moved to review queue."
      else
        "No action taken."
      end

      redirect_back fallback_location: admin_topics_path, notice: notice
    end

    private

    def sort_topics(topics)
      default_sort = params[:review_status] == "proposed" ? "created_at" : "last_seen_at"
      params[:sort] = default_sort if params[:sort].blank?
      params[:direction] = "desc" if params[:direction].blank?
      column = %w[name status importance last_seen_at last_activity_at created_at mentions_count].include?(params[:sort]) ? params[:sort] : default_sort
      direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : "desc"

      if column == "mentions_count"
        topics.left_joins(:agenda_items)
              .group(:id)
              .order(Arel.sql("COUNT(agenda_items.id) #{direction}"))
      else
        topics.order(column => direction)
      end
    end

    def render_turbo_update(message)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@topic),
            partial: "admin/topics/topic",
            locals: { topic: @topic, preview_window: helpers.preview_window_from_params(params) }
          )
        }
        format.html { redirect_back fallback_location: admin_topics_path, notice: message }
      end
    end

    def set_topic
      @topic = Topic.find(params[:id])
    end

    def record_review_event(topic, action)
      return unless Current.user

      TopicReviewEvent.create!(
        topic: topic,
        user: Current.user,
        action: action,
        reason: params[:reason].presence
      )
    end

    def record_bulk_review_events(topic_ids, action, reason)
      return unless Current.user

      topic_ids.each do |topic_id|
        TopicReviewEvent.create!(
          topic_id: topic_id,
          user: Current.user,
          action: action,
          reason: reason
        )
      end
    end

    def expand_blocklist(blocked_name)
      normalized = Topic.normalize_name(blocked_name)
      TopicBlocklist.find_or_create_by(name: normalized)

      # Add similar variants via pg_trgm
      Topic.similar_to(blocked_name, 0.8)
           .where(status: "blocked")
           .where.not(name: normalized)
           .pluck(:name)
           .each do |variant|
        TopicBlocklist.find_or_create_by(name: variant)
      end
    rescue => e
      Rails.logger.warn "Blocklist expansion failed for '#{blocked_name}': #{e.message}"
    end

    def topic_params
      params.require(:topic).permit(:description, :importance, :name, :source_type, :source_notes, :resident_impact_score)
    end
  end
end
