namespace :members do
  desc "Extract committee memberships from the most recent minutes per committee"
  task extract_from_minutes: :environment do
    committees_processed = 0
    committees_skipped = 0

    Committee.find_each do |committee|
      meeting = committee.meetings
        .joins(:meeting_documents)
        .where(meeting_documents: { document_type: "minutes_pdf" })
        .where.not(meeting_documents: { extracted_text: [ nil, "" ] })
        .order(starts_at: :desc)
        .first

      unless meeting
        puts "#{committee.name}: no minutes found, skipping"
        committees_skipped += 1
        next
      end

      puts "#{committee.name}: processing #{meeting.body_name} (#{meeting.starts_at&.strftime('%Y-%m-%d')})"
      ExtractCommitteeMembersJob.perform_now(meeting.id)
      committees_processed += 1
    end

    puts "\nDone. Processed #{committees_processed} committees, skipped #{committees_skipped}."
  end

  desc "Merge one member into another (reassigns all records)"
  task :merge, [ :source_name, :target_name ] => :environment do |_t, args|
    source_name = args[:source_name]
    target_name = args[:target_name]
    abort "Usage: bin/rails members:merge[source_name,target_name]" if source_name.blank? || target_name.blank?

    source = Member.find_by(name: source_name)
    abort "Source member '#{source_name}' not found" unless source

    target = Member.find_by(name: target_name)
    abort "Target member '#{target_name}' not found" unless target

    puts "Merging '#{source.name}' into '#{target.name}'..."
    puts "  Votes: #{source.votes.count}"
    puts "  Attendances: #{source.meeting_attendances.count}"
    puts "  Memberships: #{source.committee_memberships.count}"
    puts "  Aliases: #{source.member_aliases.count}"

    source.merge_into!(target)

    puts "Done. '#{source_name}' merged into '#{target.name}' and deleted."
  end

  desc "Auto-merge single-word member names into matching full names (dry run with DRY_RUN=1)"
  task cleanup: :environment do
    dry_run = ENV["DRY_RUN"] == "1"
    puts dry_run ? "DRY RUN — no changes will be made" : "Running cleanup..."

    single_word_members = Member.where("name NOT LIKE '% %'")
    puts "Found #{single_word_members.count} single-word member names"

    single_word_members.find_each do |member|
      candidates = Member.where("name ILIKE ? AND id != ?", "% #{ActiveRecord::Base.sanitize_sql_like(member.name)}", member.id)
      if candidates.count == 1
        target = candidates.first
        if dry_run
          puts "  WOULD MERGE: '#{member.name}' -> '#{target.name}'"
        else
          print "  Merging '#{member.name}' -> '#{target.name}'... "
          member.merge_into!(target)
          puts "done"
        end
      elsif candidates.count > 1
        puts "  AMBIGUOUS: '#{member.name}' matches: #{candidates.pluck(:name).join(', ')}"
      else
        puts "  NO MATCH: '#{member.name}'"
      end
    end
  end

  desc "List potential duplicate members for review"
  task list_duplicates: :environment do
    members = Member.order(:name).pluck(:id, :name)
    puts "Checking #{members.size} members for potential duplicates...\n\n"

    by_last_name = members.group_by { |_id, name| name.split.last&.downcase }

    by_last_name.each do |last_name, group|
      next if group.size < 2

      puts "#{last_name.capitalize} (#{group.size} members):"
      group.each do |id, name|
        aliases = MemberAlias.where(member_id: id).pluck(:name)
        alias_str = aliases.any? ? " (aliases: #{aliases.join(', ')})" : ""
        votes = Vote.where(member_id: id).count
        attendances = MeetingAttendance.where(member_id: id).count
        puts "  [#{id}] #{name} — #{votes} votes, #{attendances} attendances#{alias_str}"
      end
      puts
    end
  end
end
