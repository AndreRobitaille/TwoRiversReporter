module Admin
  class TopicsController < BaseController
    before_action :set_topic, only: %i[show update approve block unblock needs_review pin unpin merge create_alias]

    def index
      scope = filtered_topics
      @inbox_rows = Admin::Topics::InboxQuery.new(scope: scope, sort: params[:sort]).call
    end

    def show
      @workspace = Admin::Topics::DetailWorkspaceQuery.new(topic: @topic).call
      @impact_preview = build_impact_preview
      @retire_preview = Admin::Topics::ImpactPreviewQuery.new(action: :retire, topic: @topic).call
      @detail_workspace_context = detail_workspace_context
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
          format.html do
            @workspace = Admin::Topics::DetailWorkspaceQuery.new(topic: @topic).call
            @impact_preview = build_impact_preview
            @retire_preview = Admin::Topics::ImpactPreviewQuery.new(action: :retire, topic: @topic).call
            flash.now[:alert] = @topic.errors.full_messages.to_sentence
            render :show, status: :unprocessable_entity
          end
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
      ::Topics::GenerateDescriptionJob.perform_later(@topic.id)
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

      ::Topics::MergeService.new(source_topic: @topic, target_topic: target_topic).call

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
      topics = Topic.search_by_text(params[:q]).limit(20)
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
        topics.each { |t| ::Topics::GenerateDescriptionJob.perform_later(t.id) }
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

    def filtered_topics
      scope = Topic.all
      scope = scope.where(status: params[:status]) if params[:status].present?
      scope = scope.where(review_status: params[:review_status]) if params[:review_status].present?
      scope = scope.where(lifecycle_status: params[:lifecycle_status]) if params[:lifecycle_status].present?
      scope = scope.pinned if params[:pinned] == "true"
      scope = scope.search_by_text(params[:q]) if params[:q].present?
      scope
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

    def build_impact_preview
      source_topic = Topic.find_by(id: params[:source_topic_id])
      action = params[:action_name].presence&.to_sym || :merge
      Admin::Topics::ImpactPreviewQuery.new(action: action, topic: @topic, source_topic: source_topic).call
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

    def detail_workspace_context
      params.permit(:source_topic_id, :q).to_h.compact_blank.symbolize_keys
    end
  end
end
