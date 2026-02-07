module Admin
  class TopicBlocklistsController < BaseController
    def index
      @blocklists = TopicBlocklist.order(name: :asc)
    end

    def create
      @blocklist = TopicBlocklist.new(blocklist_params)
      if @blocklist.save
        redirect_to admin_topic_blocklists_path, notice: "Added to blocklist."
      else
        redirect_to admin_topic_blocklists_path, alert: "Failed to add to blocklist: #{@blocklist.errors.full_messages.join(', ')}"
      end
    end

    def destroy
      @blocklist = TopicBlocklist.find(params[:id])
      @blocklist.destroy
      redirect_to admin_topic_blocklists_path, notice: "Removed from blocklist."
    end

    private

    def blocklist_params
      params.require(:topic_blocklist).permit(:name, :reason)
    end
  end
end
