module Admin::ElectionsHelper
  def election_work_items(workspace)
    items = workspace.leads.map do |key, lead|
      source = workspace.sources[lead.fetch("url")]
      if source
        saved_election_item(source, lead.fetch("short_title"), listed: true)
      elsif lead.fetch("kind") == "article"
        { title: lead.fetch("short_title"), status: "Article found · Answers needed", action: "Add Council answers",
          hint: "Save the City Council questions and answers once for everyone in the race.",
          path: new_admin_campaign_source_path(year: workspace.year, lead: key), attention: true }
      else
        ready = Campaigns::ElectionBackfill.caption_path(lead)
        if !ready && lead["preparing_captions"]
          next { title: lead.fetch("short_title"), status: "Preparing captions", action: "Watch recording",
            path: lead.fetch("url"), attention: false }
        end
        { title: lead.fetch("short_title"), status: ready ? "Captions ready · Speakers needed" : "Caption file needed",
          action: ready ? "Label speakers" : "Upload captions", path: desk_admin_campaign_forum_path(year: workspace.year, lead: key),
          source_url: lead.fetch("url"), attention: true }
      end
    end

    workspace.sources.except(*workspace.leads.values.pluck("url")).each_value do |source|
      items << saved_election_item(source, source.forum? ? source.title : "#{source.publisher} questionnaire")
    end
    if workspace.edition["questionnaire_note"] && workspace.sources.values.none? { |source| !source.forum? && Campaigns::ElectionBackfill.htr?(source) }
      items << { title: "HTR News questionnaire", status: "Source needed", hint: "The HTR article hasn’t been located.",
        action: "Add HTR article", path: new_admin_campaign_source_path(year: workspace.year), attention: true }
    end
    items
  end

  private

  def saved_election_item(source, title, listed: false)
    if source.forum?
      version = source.current_version
      label_path = listed && version.prepared_transcript.key?("original_json")
      complete = version.extraction&.status == "completed"
      progress = Admin::QuestionnaireProgress.new(version) unless complete
      return { title: title, status: "Speaker labels saved · #{complete ? 'Analysis complete' : progress.label}",
        action: complete && label_path ? "Review labels" : "Open saved forum",
        path: complete && label_path ? desk_admin_campaign_forum_path(source_id: source) : admin_campaign_source_path(source),
        hint: (progress.guidance unless complete), attention: !complete && progress.needs_attention?,
        source_url: (source.source_url if complete && label_path), version: version.id }
    end

    progress = Admin::QuestionnaireProgress.new(source.current_version)
    { title: title, status: "Answers saved · #{progress.label}", action: progress.needs_attention? ? "Open analysis" : "Read answers",
      hint: (progress.guidance if progress.needs_attention?), path: admin_campaign_source_path(source), attention: progress.needs_attention? }
  end
end
