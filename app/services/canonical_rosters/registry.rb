module CanonicalRosters
  class Registry
    SOURCES = [
      CityCouncilSource,
      CityManagerSource,
      ExploreTwoRiversSource,
      MainStreetSource
    ].freeze

    def self.fetch(fetcher: HttpFetcher.new)
      SOURCES.map { |source| source.new(fetcher: fetcher).call }
    end
  end
end
