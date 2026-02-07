module Admin
  class TopicsController < BaseController
    before_action :set_topic, only: %i[show update approve block unblock pin unpin merge create_alias]

    def index
      @topics = Topic.all

      if params[:status].present?
        @topics = @topics.where(status: params[:status])
      end

      if params[:pinned] == "true"
        @topics = @topics.pinned
      end

      if params[:q].present?
        @topics = @topics.similar_to(params[:q])
      else
        @topics = @topics.order(last_seen_at: :desc, created_at: :desc)
      end

      # Simple pagination
      @page = [ params[:page].to_i, 1 ].max
      @per_page = 50

      # execute count before limit/offset
      @total_topics = @topics.count
      @total_pages = (@total_topics.to_f / @per_page).ceil

      @topics = @topics.offset((@page - 1) * @per_page).limit(@per_page)
    end

    def show
      @aliases = @topic.topic_aliases
      @recent_mentions = @topic.agenda_items.includes(:meeting).order("meetings.starts_at DESC").limit(10)
    end

    def update
      if @topic.update(topic_params)
        redirect_to admin_topic_path(@topic), notice: "Topic updated."
      else
        render :show, status: :unprocessable_entity
      end
    end

    def approve
      @topic.update(status: "approved")
      render_turbo_update("Topic approved.")
    end

    def block
      @topic.update(status: "blocked")
      render_turbo_update("Topic blocked.")
    end

    def unblock
      # Default to approved as that is now the standard state
      @topic.update(status: "approved")
      render_turbo_update("Topic unblocked.")
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

    private

    def render_turbo_update(message)
      respond_to do |format|
        format.turbo_stream {
          render turbo_stream: turbo_stream.replace(
            helpers.dom_id(@topic),
            partial: "admin/topics/topic",
            locals: { topic: @topic }
          )
        }
        format.html { redirect_back fallback_location: admin_topics_path, notice: message }
      end
    end

    def set_topic
      @topic = Topic.find(params[:id])
    end

    def topic_params
      params.require(:topic).permit(:summary, :importance, :name)
    end
  end
end
