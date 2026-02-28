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
end
