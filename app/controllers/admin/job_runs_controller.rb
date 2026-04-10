class Admin::JobRunsController < Admin::BaseController
  JOB_TYPES = {
    # Meeting-scoped
    "extract_topics" => { job: ExtractTopicsJob, scope: :meeting, name: "Extract Topics" },
    "extract_votes" => { job: ExtractVotesJob, scope: :meeting, name: "Extract Votes" },
    "extract_committee_members" => { job: ExtractCommitteeMembersJob, scope: :meeting, name: "Extract Committee Members" },
    "summarize_meeting" => { job: SummarizeMeetingJob, scope: :meeting, name: "Summarize Meeting" },
    # Topic-scoped
    "generate_topic_briefing" => { job: Topics::GenerateTopicBriefingJob, scope: :topic, name: "Topic Briefing" },
    "generate_description" => { job: Topics::GenerateDescriptionJob, scope: :topic, name: "Topic Description" },
    # No-target
    "auto_triage" => { job: Topics::AutoTriageJob, scope: :none, name: "Topic Triage" },
    "discover_meetings" => { job: Scrapers::DiscoverMeetingsJob, scope: :none, name: "Scrape City Website" }
  }.freeze

  def index
    @job_types = JOB_TYPES
    @committees = Committee.active.order(:name)
  end

  def create
    job_type = params[:job_type]
    config = JOB_TYPES[job_type]

    unless config
      redirect_to admin_job_runs_path, alert: "Unknown job type."
      return
    end

    targets = resolve_targets(config, params)
    enqueue_jobs(config, targets)

    count_text = targets ? "#{targets.size} #{config[:name]}" : "1 #{config[:name]}"
    redirect_to admin_job_runs_path, notice: "Enqueued #{count_text} job(s)."
  end

  def count
    config = JOB_TYPES[params[:job_type]]
    return render json: { count: 0 } unless config

    targets = resolve_targets(config, params)
    render json: { count: targets&.size || 1 }
  end

  private

  def resolve_targets(config, params)
    case config[:scope]
    when :meeting
      scope = Meeting.all
      scope = scope.where(starts_at: params[:date_from]..params[:date_to]) if params[:date_from].present? && params[:date_to].present?
      scope = scope.where(committee_id: params[:committee_id]) if params[:committee_id].present?
      scope.to_a
    when :topic
      if params[:topic_ids].present?
        Topic.where(id: params[:topic_ids]).to_a
      else
        Topic.approved.to_a
      end
    when :none
      nil
    end
  end

  def enqueue_jobs(config, targets)
    case config[:scope]
    when :meeting
      targets.each { |meeting| config[:job].perform_later(meeting.id) }
    when :topic
      if config[:job] == Topics::GenerateTopicBriefingJob
        targets.each do |topic|
          latest_meeting_id = Meeting.where(id: topic.agenda_items.select(:meeting_id)).order(starts_at: :desc).pick(:id)
          config[:job].perform_later(topic_id: topic.id, meeting_id: latest_meeting_id) if latest_meeting_id
        end
      else
        targets.each { |topic| config[:job].perform_later(topic.id) }
      end
    when :none
      config[:job].perform_later
    end
  end
end
