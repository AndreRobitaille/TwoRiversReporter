module CouncilProfiles
  class RefreshTermSummariesJob < ApplicationJob
    queue_with_priority 50

    # Discovery fans out to asynchronous downloads, evidence extraction and
    # comparisons. Let that run settle before taking the weekly snapshot.
    INTAKE_JOBS = %w[Scrapers::ParseMeetingPageJob Scrapers::DiscoverTranscriptsJob Documents::DownloadTranscriptJob ReconcileCampaignSourcesJob
      Scrapers::ParseAgendaJob Documents::DownloadJob Documents::AnalyzePdfJob Documents::OcrJob ExtractVotesJob
      ExtractTopicsJob Topics::AutoTriageJob SummarizeMeetingJob ExtractCampaignSourceJob MatchCampaignTopicsJob
      MatchCampaignActionsJob MatchCampaignIssueEvidenceJob ExtractCouncilIssueUpdatesJob].freeze

    def perform(cycle, member_id = nil)
      cycle = Date.iso8601(cycle)
      return unless cycle.tuesday? && Time.current.between?(cycle.in_time_zone.change(hour: 23), (cycle + 1).end_of_day)
      current = MemberPosition.current.where(kind: "city_council")
      members = current.where(member_id: CampaignStatement.where(status: "accepted").select(:member_id))
        .or(current.where(member_id: CouncilTermSummary.select(:member_id)))
      if member_id
        member = Member.find_by(id: members.where(member_id: member_id).select(:member_id))
        return unless member
        period = ResidentContent::CouncilPeriod.new(member)
        return unless period.selected && !period.selected.ended_on
        evidence = TermEvidence.new(member, period: period)
        key = { member: member, term_started_on: period.selected.started_on }
        unless evidence.tracked?
          CouncilTermSummary.find_by(key)&.destroy!
          return
        end
        summary = CouncilTermSummary.find_or_create_by!(key)
        summary.refresh!(cycle, evidence) unless summary.attempted_cycle && summary.attempted_cycle >= cycle
      elsif intake_pending?(cycle)
        self.class.set(wait: 5.minutes).perform_later(cycle.iso8601)
      else
        members.distinct.pluck(:member_id).each { |id| self.class.perform_later(cycle.iso8601, id) }
      end
    rescue ReserveAiSpend::Paused => e
      if e.message == "live_concurrency_limit"
        self.class.set(wait: 5.minutes).perform_later(cycle.iso8601, member_id)
      else
        Rails.logger.info("Council term summary held member=#{member_id} cycle=#{cycle} reason=#{e.message}")
      end
    end

    private

    def intake_pending?(cycle)
      return false unless self.class.queue_adapter.is_a?(ActiveJob::QueueAdapters::SolidQueueAdapter)
      SolidQueue::Job.where(finished_at: nil, class_name: INTAKE_JOBS)
        .where(created_at: cycle.in_time_zone.change(hour: 23)..).where.missing(:failed_execution).exists?
    end
  end
end
