module Admin
  class ElectionWorkspace
    attr_reader :year, :current_year, :date, :edition, :sources, :years

    def initialize(requested_year, today: Date.current)
      schedule = ResidentContent::CouncilElection::SCHEDULE.fetch("elections")
      @current_year = (today.year + (today.month >= 11 ? 1 : 0)).to_s
      source_dates = CampaignSource.distinct.pluck(:election_on).sort.group_by { |day| day.year.to_s }
      historical = Campaigns::ElectionBackfill::EDITIONS
      scheduled_years = schedule.index_by { |entry| entry.fetch("election_on").first(4) }
      seasons_to_date = (scheduled_years.keys.min.to_i..current_year.to_i).map(&:to_s)
      @years = (historical.keys | source_dates.keys | seasons_to_date | [ current_year ]).sort.reverse
      @year = years.include?(requested_year) ? requested_year : current_year
      @edition = Campaigns::ElectionBackfill.for(year) || {}
      @scheduled = scheduled_years[year]
      official_date = edition["election_on"] || @scheduled&.fetch("election_on")
      @date = if official_date
        Date.iso8601(official_date)
      elsif year == current_year || seasons_to_date.include?(year)
        first_tuesday_in_april
      else
        source_dates.fetch(year).first
      end
      @sources = CampaignSource.where(election_on: date).order(:published_on, :id).index_by(&:source_url)
    end

    def leads
      edition.fetch("sources", {})
    end

    def current?
      year == current_year
    end

    def filing_edition
      @filing_edition ||= ResidentContent::CouncilElection.new(@scheduled) if @scheduled
    end

    def candidate_list_needed?(today: Date.current)
      current? && filing_edition && today < date && filing_edition.candidates.empty?
    end

    def candidate_list_due?(today: Date.current)
      candidate_list_needed?(today: today) && today > filing_edition.filing_deadline
    end

    def filing_article_url
      ElectionFilingWatch.find_by(election_on: date, stopped: false)&.article_url
    end

    def prior_sources
      return [] unless current?

      CampaignSource.where(election_on: Date.new(date.year - 3).all_year).order(:published_on, :id).to_a
    end

    private

    def first_tuesday_in_april
      april_first = Date.new(year.to_i, 4, 1)
      april_first + (2 - april_first.wday) % 7
    end
  end
end
