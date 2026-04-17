module Admin
  class TopicRepairsController < BaseController
    before_action :set_topic

    def show
      redirect_to admin_topic_url(@topic, detail_workspace_context)
    end

    def history
      @history = @topic.topic_review_events.includes(:user).order(created_at: :desc).limit(10)

      render :history
    end

    def merge_candidates
      @candidates = Admin::Topics::MergeCandidatesQuery.new(topic: @topic, query: params[:q]).call
      @select_action = if %w[move_alias merge_away topic_to_alias].include?(params[:mode])
        "topic-repair-search#selectCandidate"
      else
        "topic-detail-impact#selectCandidate"
      end

      render partial: "admin/topic_repairs/merge_candidates", locals: { topic: @topic, candidates: @candidates, select_action: @select_action }
    end

    def impact_preview
      source_topic = Topic.find_by(id: params[:source_topic_id])
      target_topic = Topic.find_by(id: params[:target_topic_id])
      action = params[:action_name].presence&.to_sym || :merge
      preview_topic = case action
      when :move_alias
        target_topic || source_topic
      when :topic_to_alias
        @topic
      when :merge_away
        @topic
      else
        @topic
      end
      @workspace = Admin::Topics::ImpactPreviewQuery.new(
        action: action,
        topic: preview_topic || @topic,
        source_topic: if action == :move_alias
          nil
                      elsif action == :topic_to_alias
          target_topic
                      elsif action == :merge_away
          target_topic
                      else
          source_topic
                      end,
        alias_name: params[:alias_name],
        alias_count: params[:alias_count].presence&.to_i || (action == :move_alias ? 1 : nil)
      ).call

      render partial: "admin/topics/impact_summary", locals: { workspace: @workspace }
    end

    def move_alias
      move_params = params.permit(:alias_id, :target_topic_id, :reason)
      topic_alias = @topic.topic_aliases.find(move_params[:alias_id])
      target_topic = Topic.find(move_params[:target_topic_id])
      TopicAlias.where(id: topic_alias.id).update_all(topic_id: target_topic.id)
      record_review_event(target_topic, "alias_moved", move_params[:reason].presence)

      redirect_to admin_topic_url(@topic, detail_workspace_context), notice: "Alias moved."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Alias or target topic not found."
    end

    def merge
      source_topic = Topic.find(params[:source_topic_id])
      if source_topic.id == @topic.id
        redirect_to detail_workspace_url, alert: "Cannot combine a topic with itself."
        return
      end

      ::Topics::MergeService.new(source_topic: source_topic, target_topic: @topic).call
      record_review_event(@topic, "merged", params[:reason].presence)

      redirect_to admin_topic_url(@topic, detail_workspace_context.except(:source_topic_id)), notice: "Combined duplicate topic #{source_topic.name} into #{@topic.name}."
    rescue ActiveRecord::RecordNotFound
      redirect_to detail_workspace_url, alert: "Duplicate topic not found."
    rescue StandardError => e
      redirect_to detail_workspace_url, alert: "Combine failed: #{e.message}"
    end

    def merge_away
      if params[:reason].blank?
        redirect_to detail_workspace_url, alert: "Reason is required."
        return
      end

      destination_topic = Topic.find(params[:destination_topic_id])
      if destination_topic.id == @topic.id
        redirect_to detail_workspace_url, alert: "Cannot merge a topic into itself."
        return
      end

      ::Topics::MergeService.new(source_topic: @topic, target_topic: destination_topic).call
      record_review_event(destination_topic, "merged", params[:reason].presence)

      redirect_to admin_topic_url(destination_topic, detail_workspace_context.except(:source_topic_id)), notice: "Merged into #{destination_topic.name}."
    rescue ActiveRecord::RecordNotFound
      redirect_to detail_workspace_url, alert: "Destination topic not found."
    rescue StandardError => e
      redirect_to detail_workspace_url, alert: "Merge failed: #{e.message}"
    end

    def topic_to_alias
      if params[:reason].blank?
        redirect_to detail_workspace_url, alert: "Reason is required."
        return
      end

      destination_topic = Topic.find(params[:destination_topic_id])
      destination_topic_id = destination_topic.id
      if destination_topic.id == @topic.id
        redirect_to detail_workspace_url, alert: "Cannot move a topic under itself."
        return
      end

      ::Topics::MergeService.new(source_topic: @topic, target_topic: destination_topic).call
      record_review_event(destination_topic, "topic_rehomed", params[:reason].presence)

      redirect_to admin_topic_url(destination_topic_id), notice: "#{@topic.name} is now an alias of #{destination_topic.name}."
    rescue ActiveRecord::RecordNotFound
      redirect_to detail_workspace_url, alert: "Destination topic not found."
    rescue StandardError => e
      redirect_to detail_workspace_url, alert: "Topic-to-alias failed: #{e.message}"
    end

    def flip_alias
      ::Topics::FlipAliasService.new(topic: @topic).call
      record_review_event(@topic, "alias_flipped", nil)

      redirect_to admin_topic_url(@topic, detail_workspace_context), notice: "Topic name and only alias were swapped."
    rescue StandardError => e
      redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Flip failed: #{e.message}"
    end

    def update_alias
      topic_alias = @topic.topic_aliases.find(params[:alias_id])

      if topic_alias.update(name: params[:name])
        record_review_event(topic_alias.topic, "alias_renamed", params[:reason].presence)
        redirect_to admin_topic_url(@topic, detail_workspace_context), notice: "Alias updated."
      else
        redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Alias update failed: #{topic_alias.errors.full_messages.join(', ')}"
      end
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Alias not found."
    end

    def remove_alias
      topic_alias = @topic.topic_aliases.find(params[:alias_id])
      ::Topics::RemoveAliasService.new(topic_alias: topic_alias, reason: params[:reason].presence).call

      redirect_to admin_topic_url(@topic, detail_workspace_context), notice: "Alias removed."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Alias not found."
    end

    def promote_alias
      topic_alias = @topic.topic_aliases.find(params[:alias_id])
      promoted_topic = ::Topics::PromoteAliasService.new(topic_alias: topic_alias, reason: params[:reason].presence).call

      redirect_to admin_topic_url(promoted_topic, source_topic_id: @topic.id, source_topic_name: @topic.name, q: @topic.name), notice: "Created topic #{promoted_topic.name}. Continue the canonical cleanup there."
    rescue ActiveRecord::RecordNotFound
      redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Alias not found."
    rescue StandardError => e
      redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Alias promotion failed: #{e.message}"
    end

    def retire
      if params[:reason].blank?
        redirect_to admin_topic_url(@topic, detail_workspace_context), alert: "Reason is required."
        return
      end

      Topic.transaction do
        @topic.update!(status: "blocked", review_status: "blocked")
        record_review_event(@topic, "retired", params[:reason].presence)
        expand_blocklist(@topic.name)
      end

      redirect_to admin_topic_url(@topic, detail_workspace_context), notice: "Topic retired."
    end

    private

    def set_topic
      @topic = Topic.find(params[:id])
    end

    def record_review_event(topic, action, reason)
      return unless Current.user

      TopicReviewEvent.create!(topic: topic, user: Current.user, action: action, reason: reason)
    end

    def expand_blocklist(blocked_name)
      normalized = Topic.normalize_name(blocked_name)
      TopicBlocklist.find_or_create_by(name: normalized)

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

    def detail_workspace_url
      admin_topic_url(@topic, detail_workspace_context)
    end

    def detail_workspace_context
      params.permit(:source_topic_id, :q).to_h.compact_blank.symbolize_keys
    end
  end
end
