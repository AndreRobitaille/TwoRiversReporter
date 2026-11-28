namespace :elections do
  desc "Record a reviewed local backfill cohort's oaths from the matching official packet"
  task :backfill_terms, [ :year, :packet_file ] => :environment do |_task, args|
    abort "Select a local development database." unless Rails.env.development?
    edition = Campaigns::ElectionBackfill.for(args.fetch(:year)) || abort("Unknown backfill year.")
    oath = edition["term_start"] || abort("This election has no oath packet configured for backfill.")
    path = args.fetch(:packet_file)
    sha = Digest::SHA256.file(path).hexdigest
    abort "Packet differs from the reviewed source." unless sha == oath.fetch("sha256")
    started_on = Date.iso8601(oath.fetch("started_on"))
    key = "#{started_on.year}-election"
    members = edition.fetch("term_members").map { |name| Member.find_by!(name: name) }
    CouncilServicePeriod.transaction do
      date = Date.iso8601(oath.fetch("meeting_on"))
      document = MeetingDocument.find_by(source_url: oath.fetch("packet"))
      unless document
        meetings = Meeting.where(starts_at: date.all_day).select { |row| row.body_name == "City Council Meeting" }
        raise "Ambiguous Council packet meeting." if meetings.many?
        meeting = meetings.first || Meeting.find_or_create_by!(detail_page_url: oath.fetch("meeting_url")) do |row|
          row.assign_attributes(starts_at: date.in_time_zone.change(hour: 18), body_name: "City Council Meeting",
            committee: Committee.resolve("City Council"), status: "held", meeting_type: "regular")
        end
        document = meeting.meeting_documents.create!(source_url: oath.fetch("packet"), document_type: "packet_pdf")
      end
      raise "The local packet has different bytes." if document.sha256.present? && document.sha256 != sha
      version = document.current_source_version
      unless version
        document.update!(sha256: sha, fetched_at: Time.current)
        blob = File.open(path, "rb") do |io|
          ActiveStorage::Blob.create_and_upload!(io: io, filename: "council-packet-#{date}.pdf", content_type: "application/pdf")
        end
        document.file.attach(blob)
        version = MeetingDocumentVersion.capture!(document)
      end
      blob = version.file.blob
      unless blob.service.exist?(blob.key)
        File.open(path, "rb") { |io| blob.service.upload(blob.key, io, checksum: blob.checksum) }
      end
      missing = members.reject do |member|
        prior = CouncilServicePeriod.find_by(member: member, period_key: key)
        if prior && prior.started_on != started_on
          raise "Existing term date conflicts for #{member.name}."
        end
        prior.present?
      end
      CouncilServicePeriod.record_starts!(period_key: key, source_version: version, page: oath.fetch("page"),
        entries: missing.map { |m| { member_id: m.id, started_on: started_on } })
    end
    puts "#{key}: #{members.size} sourced service periods."
  end

  desc "Prepare checked public sources for a historical local election, leaving speaker review to the editor"
  task :prepare, [ :year ] => :environment do |_task, args|
    require "open-uri"
    require "open3"
    require "tempfile"
    abort "Select a local development database." unless Rails.env.development?
    year = args.fetch(:year)
    edition = Campaigns::ElectionBackfill.for(year) || abort("Unknown election.")
    oath = edition["term_start"] || abort("This election has no oath packet configured for backfill.")
    Tempfile.create([ "election-oaths", ".pdf" ]) do |file|
      file.binmode
      URI.open(oath.fetch("packet")) { |source| IO.copy_stream(source, file) }
      file.flush
      task = Rake::Task["elections:backfill_terms"]
      task.reenable
      task.invoke(year, file.path)
    end
    edition.fetch("sources").each_value do |lead|
      if lead["kind"] == "forum"
        id = URI.decode_www_form(URI(lead.fetch("url")).query).to_h.fetch("v")
        unless system(Rails.root.join("bin/prepare-forum-captions").to_s, id)
          puts "#{lead.fetch('title')}: supply media or captions in the speaker desk."
        end
      elsif !CampaignSource.exists?(source_url: lead.fetch("url"))
        unless lead["body_selector"]
          puts "#{lead.fetch('title')}: add the Council responses in Elections."
          next
        end
        # A publisher-specific selector limits intake to the reviewed questionnaire.
        html, status = Open3.capture2("curl", "--fail", "--silent", "--show-error", "--location", "--max-time", "30", lead.fetch("url"))
        unless status.success?
          puts "#{lead.fetch('title')}: paste permitted article text in Elections."
          next
        end
        begin
          Campaigns::ElectionBackfill.import_questionnaire!(edition, lead, html)
        rescue ArgumentError => error
          puts "#{lead.fetch('title')}: #{error.message}"
        end
      end
    end
  end
end

namespace :elections do
  desc "Record the municipal canvass. Supply YEAR, CONFIRMED_ON, SOURCE_URL and WINNERS (one filed name per line)."
  task confirm_result: :environment do
    date = Campaigns::ElectionBackfill.election_on(ENV.fetch("YEAR")) || abort("Unknown election")
    CouncilElectionResult.confirm!(election_on: date, confirmed_on: Date.iso8601(ENV.fetch("CONFIRMED_ON")),
      source_url: ENV.fetch("SOURCE_URL"), winner_names: ENV.fetch("WINNERS").lines.map(&:strip).compact_blank)
  end
end
