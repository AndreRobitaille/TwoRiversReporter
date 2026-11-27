class RefreshCandidatePortraitJob < ApplicationJob
  retry_on Campaigns::PortraitImage::Error, wait: :polynomially_longer, attempts: 4

  def perform(name)
    member = Member.find_by(name: name) || MemberAlias.find_by(name: name)&.member
    names = member ? [ member.name, *member.member_aliases.pluck(:name) ] : [ name ]
    CandidatePortrait.transaction do
      # Imports and retries for aliases of the same person must choose from the
      # same committed articles before replacing their one public thumbnail.
      connection = CandidatePortrait.connection
      key = connection.quote("candidate-portrait:#{names.first}")
      connection.execute("SELECT pg_advisory_xact_lock(hashtextextended(#{key}, 0))")
      portrait = (CandidatePortrait.find_by(member: member) if member) || CandidatePortrait.find_by(name: names)
      if (photo = Campaigns::LatestPortrait.for(names))
        portrait ||= CandidatePortrait.new
        portrait.thumbnail = Campaigns::PortraitImage.thumbnail(photo.image_url) if portrait.image_url != photo.image_url
        portrait.update!(name: names.first, member: member, image_url: photo.image_url, source_url: photo.source_url, publisher: photo.publisher)
      else
        portrait&.destroy!
      end
    end
  end
end
