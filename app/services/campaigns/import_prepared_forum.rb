module Campaigns
  class ImportPreparedForum
    def self.call(file:, actor:, attributes:, gaps_are_moderator: false, source: nil)
      raise PreparedForum::InvalidFile, "Choose a speaker-labeled JSON file." unless file.respond_to?(:read)

      prepared = PreparedForum.new(file.read(PreparedForum::MAX_BYTES + 1), verified_by: actor,
        gaps_are_moderator: gaps_are_moderator).call
      if source && source.source_url != prepared.fetch(:source_url)
        raise PreparedForum::InvalidFile, "The replacement must refer to the same recording."
      end
      existing = CampaignSource.find_by(source_url: prepared.fetch(:source_url))
      return [ existing, false ] if existing && source.nil?

      source ||= CampaignSource.new
      source.assign_attributes(attributes.merge(prepared))
      source.submitted_by = actor
      source.save!
      [ source, true ]
    end
  end
end
