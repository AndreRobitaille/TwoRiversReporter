module Admin
  class CampaignForumsController < BaseController
    before_action :set_replacement

    def new
      @values = @replacement&.attributes&.slice("publisher", "published_on", "election_on", "coverage_notes") || {}
    end

    def create
      input = params.require(:forum)
      @values = input.permit(:publisher, :published_on, :election_on, :coverage_notes).to_h
      unless input[:speaker_verified] == "1"
        raise Campaigns::PreparedForum::InvalidFile, "Confirm that the speaker labels were checked against the recording."
      end
      source, saved = Campaigns::ImportPreparedForum.call(file: input[:file], actor: Current.user,
        attributes: @values.symbolize_keys, source: @replacement, gaps_are_moderator: input[:gaps_are_moderator] == "1")
      redirect_to admin_campaign_source_path(source), notice: saved ? "Forum saved." : "This recording is already saved. Use Replace transcript to correct it."
    rescue Campaigns::PreparedForum::InvalidFile, ActiveRecord::RecordInvalid => e
      @error = e.message
      render :new, status: :unprocessable_entity
    end

    private

    def set_replacement
      source_id = params[:source_id].presence || params.dig(:forum, :source_id).presence
      return unless source_id

      @replacement = CampaignSource.find(source_id)
      raise ActiveRecord::RecordNotFound unless @replacement.forum?
    end
  end
end
