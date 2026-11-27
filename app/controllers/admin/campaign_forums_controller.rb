module Admin
  class CampaignForumsController < BaseController
    before_action :set_replacement, only: %i[new create desk]

    def new
      @values = @replacement&.attributes&.slice("publisher", "published_on", "election_on", "coverage_notes") || {}
    end

    def desk
      if request.format.json?
        raise ActiveRecord::RecordNotFound unless @replacement
        no_store
        return render json: @replacement.prepared_transcript.fetch("original_json")
      end
      @year = @replacement&.election_on&.year&.to_s || params[:year]
      @edition = Campaigns::ElectionBackfill.for(@year) || workspace_edition
      @recordings = @edition.fetch("sources", {}).select { |_key, lead| lead["kind"] == "forum" }
      urls = @recordings.values.pluck("url")
      @saved_ids = CampaignSource.where(source_url: urls).pluck(:source_url, :id).to_h
      @lead = Campaigns::ElectionBackfill.lead(params[:year], params[:lead], kind: "forum") || {}
      if @replacement
        @lead = { "title" => @replacement.title, "url" => @replacement.source_url }
        @values = @replacement.attributes.slice("publisher", "published_on", "election_on", "coverage_notes")
        return
      end
      @values = @lead.slice("publisher", "published_on").merge("election_on" => @edition["election_on"])
    end

    def recording
      lead = Campaigns::ElectionBackfill.lead(params[:year], params[:lead], kind: "forum")
      path = Campaigns::ElectionBackfill.caption_path(lead)
      raise ActiveRecord::RecordNotFound unless path

      no_store
      send_file path, type: "text/vtt", disposition: "inline"
    end

    def captions
      upload = params[:captions]
      raise Campaigns::PreparedForum::InvalidFile, "Choose an SRT or VTT file." unless upload.respond_to?(:read)
      raw = upload.read(Campaigns::PreparedForum::MAX_BYTES + 1).force_encoding(Encoding::UTF_8)
      raise Campaigns::PreparedForum::InvalidFile, "Caption file is too large." if raw.bytesize > Campaigns::PreparedForum::MAX_BYTES

      no_store
      render json: { hash: Digest::SHA256.hexdigest(raw), words: Campaigns::ForumCaptions.words(raw) }
    rescue Campaigns::PreparedForum::InvalidFile => e
      render json: { error: e.message }, status: :unprocessable_entity
    end

    def create
      input = params.require(:forum)
      @values = input.permit(:publisher, :published_on, :election_on, :coverage_notes).to_h
      unless input[:speaker_verified] == "1"
        raise Campaigns::PreparedForum::InvalidFile, "Confirm that the speaker labels were checked against the recording."
      end
      source, saved = Campaigns::ImportPreparedForum.call(file: input[:file], actor: Current.user,
        attributes: @values.symbolize_keys, source: @replacement, gaps_are_moderator: input[:gaps_are_moderator] == "1")
      notice = saved ? "Forum saved." : "This recording is already saved. Use Edit speaker labels to correct it."
      if request.format.json?
        flash[:notice] = notice
        render json: { location: admin_campaign_source_path(source), saved: saved }
      else
        redirect_to admin_campaign_source_path(source), notice: notice
      end
    rescue Campaigns::PreparedForum::InvalidFile, ActiveRecord::RecordInvalid => e
      @error = e.message
      respond_to do |format|
        format.html { render :new, status: :unprocessable_entity }
        format.json { render json: { error: @error }, status: :unprocessable_entity }
      end
    end

    private

    def workspace_edition
      return {} unless @year

      workspace = ElectionWorkspace.new(@year)
      return {} unless workspace.year == @year

      { "election_on" => workspace.date.iso8601, "candidates" => workspace.scheduled&.fetch("candidates", {})&.keys || [] }
    end

    def set_replacement
      source_id = params[:source_id].presence || params.dig(:forum, :source_id).presence
      return unless source_id

      @replacement = CampaignSource.find(source_id)
      raise ActiveRecord::RecordNotFound unless @replacement.forum?
    end
  end
end
