module CouncilHistory
  class Batch
    FIRST = Date.new(2024, 4, 16)
    LAST = Date.new(2025, 7, 6)
    PILOT = {
      "2024-10-28" => "MEET-Minutes-aafbed31cb9749cc86ef5ad95ff3cd5c.pdf",
      "2025-05-05" => "MEET-Minutes-0a069b395b7b4040b2b46a2a7190f8f0.pdf"
    }.freeze

    STAGES = %w[facts topics summaries comparisons].freeze

    def initialize(rows, pilot: false, reviewed_facts: [], reviewed_comparisons: [], actor: nil, pilot_reuse_url: nil)
      @rows = Inventory.review(rows)
      @pilot = pilot
      @comparisons = reviewed_comparisons.group_by { |r| Time.iso8601(r.fetch("starts_at")) }
      @actor = actor
      raise ArgumentError, "Reviewed comparisons require an administrator" if @comparisons.any? && !actor&.admin?
      @reviewed_facts = reviewed_facts.group_by { |r| r.fetch("url") }
      raise ArgumentError, "Unknown pilot reuse source" if pilot_reuse_url && !@reviewed_facts.key?(pilot_reuse_url)
      @pilot_reuse_url = pilot_reuse_url
    end

    def call
      @rows.sort_by { |row| [ row.fetch("title").match?(/council/i) ? 0 : 1, row.fetch("starts_at") ] }.each do |row|
        date = Time.iso8601(row.fetch("starts_at")).in_time_zone.to_date
        raise ArgumentError, "Outside historical window" unless date.between?(FIRST, LAST)
        if @pilot
          url = row.fetch("documents")["minutes_pdf"]
          next unless url.present? && row.fetch("title").match?(/City Council/i) &&
            (File.basename(URI(url).path) == PILOT[date.iso8601] || url == @pilot_reuse_url)
        end
        next unless row.fetch("disposition").in?(%w[fetch_minutes usable no_minutes_link])
        result = begin
          process(row)
        rescue CouncilProfiles::ReserveAiSpend::Paused, Citations::SourceCatalog::InvalidSource, Topics::TriageResponse::Invalid, JSON::ParserError => error
          # Keep the source and completed stages. A later, smaller request may
          # fit the remaining allowance even when this one did not.
          row.merge("held" => error.class.name, "reason" => error.message.truncate(250))
        end
        yield result if block_given?
      end
    end

    # Repair explicitly selected later meetings using their existing documents.
    def repair_saved(meeting, stages:)
      raise ArgumentError, "Expected a later held meeting" unless meeting.starts_at && meeting.starts_at.to_date > LAST &&
        meeting.starts_at <= Time.current && !meeting.cancelled?
      raise ArgumentError, "Select the missing stages" unless stages.any? && (stages - STAGES).empty?
      raise ArgumentError, "No readable saved minutes" unless meeting.latest_document("minutes_pdf")&.extracted_text.present?
      Execution.set(meeting_id: meeting.id, pilot: false) { run_stages(meeting, stages) }
      outcome(meeting)
    end

    private

    def process(row)
      meeting = Meeting.transaction do
        key = ApplicationRecord.connection.quote(row.fetch("url"))
        ApplicationRecord.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{key}))")
        existing, conflict = Inventory.destination(row)
        raise "Meeting identity changed" if conflict
        existing || Meeting.create!(starts_at: Time.iso8601(row.fetch("starts_at")), body_name: row.fetch("title"),
          detail_page_url: row.fetch("url"), committee: Committee.resolve(row.fetch("title")), status: "held", meeting_type: "regular")
      end
      Execution.set(meeting_id: meeting.id, pilot: @pilot) do
        # A separate operator process owns this batch. All Rails job follow-ups
        # are suppressed in this execution context; each scoped stage runs here.
        prepare_documents(meeting, row) unless row.fetch("disposition") == "no_minutes_link"
        run_stages(meeting, STAGES) if meeting.latest_document("minutes_pdf")&.extracted_text.present?
      end
      Inventory.review([ row ]).first.merge(outcome(meeting))
    end

    def run_stages(meeting, stages)
      extract_facts(meeting) if stages.include?("facts")
      if stages.include?("topics")
        if meeting.agenda_items.substantive.exists? && !meeting.processing_state["topics_extraction_status"].in?(%w[processed empty])
          Execution.set(stage: "topics") { ExtractTopicsJob.perform_now(meeting.id) }
        end
        triage_topics(meeting)
      end
      if stages.include?("summaries")
        if SummarizeMeetingJob.summary_repair_needed?(meeting.reload)
          Execution.set(stage: "meeting_and_topic_summaries") { SummarizeMeetingJob.perform_now(meeting.id, enqueue_followups: false) }
        else
          Execution.set(stage: "topic_summaries") { SummarizeMeetingJob.perform_now(meeting.id, mode: :missing_topic_summaries) }
        end
      end
      return unless stages.include?("comparisons")
      saved = @comparisons.fetch(meeting.starts_at, [])
      Campaigns::ReviewedComparisons.call(saved, actor: @actor) if saved.any?
      Execution.set(stage: "promise_comparisons") do
        MatchCampaignActionsJob.perform_now(meeting.id)
        MatchCampaignIssueEvidenceJob.perform_now(meeting_id: meeting.id)
      end
    end

    def outcome(meeting)
      { "meeting_id" => meeting.id, "stages" => meeting.reload.processing_state,
        "comparisons" => CampaignActionReview.where(meeting: meeting).group(:status).count }
    end

    def prepare_documents(meeting, row)
      # Existing accepted facts can depend on the original agenda identities.
      # Do not introduce a new agenda structure into an already-analyzed meeting.
      docs = row.fetch("documents").except("packet_pdf")
      if meeting.motions.exists? || meeting.meeting_attendances.exists? || meeting.agenda_items.exists?
        docs = docs.slice("minutes_pdf")
      end
      docs.sort_by { |kind, _| kind == "minutes_pdf" ? 1 : 0 }.each do |type, url|
        next if type == "agenda_pdf" && meeting.latest_document("agenda_html")&.file&.attached?
        doc = meeting.meeting_documents.find_or_initialize_by(source_url: url)
        next if doc.persisted? && doc.document_type != type
        # Keep a usable accepted projection intact when resuming.
        next if doc.persisted? && doc.extracted_text.present?
        doc.update!(document_type: type) if doc.new_record?
        Documents::DownloadJob.perform_now(doc.id) unless doc.file.attached?
        next unless doc.reload.file.attached?
        if type.end_with?("_pdf")
          Documents::AnalyzePdfJob.perform_now(doc.id)
          Documents::OcrJob.perform_now(doc.id) if doc.reload.text_quality == "image_scan"
        elsif type == "agenda_html" && !meeting.agenda_items.exists?
          Scrapers::ParseAgendaJob.perform_now(meeting.id)
        end
      end
    end

    def triage_topics(meeting)
      proposed = meeting.topics.where(status: "proposed").where.not(id: AgendaItemTopic.joins(:agenda_item)
        .where.not(agenda_items: { meeting_id: meeting.id }).select(:topic_id))
      signature = -> { CouncilProfiles::ReserveAiSpend.request_digest(topics: proposed.reorder(:id).pluck(:id, :updated_at)) }
      ids = proposed.ids.uniq
      return if ids.empty? || meeting.processing_state["historical_triage_input"] == signature.call
      Execution.set(stage: "topic_triage") do
        Topics::TriageTool.call(apply: true, dry_run: false, topic_ids: ids)
      end
      meeting.with_lock do
        meeting.update!(processing_state: meeting.processing_state.merge("historical_triage_input" => signature.call))
      end
    end

    def extract_facts(meeting)
      # Keep legacy published roll calls intact. A source without compatible
      # saved extraction stages needs individual review before replacing facts.
      if meeting.motions.exists? || meeting.meeting_attendances.exists?
        return unless meeting.minutes_publication_id
      end
      rows = @reviewed_facts.fetch(meeting.latest_document("minutes_pdf").source_url, [])
      ReviewedFacts.apply(meeting, rows) if rows.any?
      Minutes::Publish.call(meeting) if rows.any?
      { "votes" => ExtractVotesJob, "attendance" => ExtractCommitteeMembersJob }.each do |kind, job|
        next unless Minutes::Pipeline.needed?(meeting.reload, kind)
        Execution.set(stage: kind) { job.perform_now(meeting.id) }
      end
    end
  end
end
