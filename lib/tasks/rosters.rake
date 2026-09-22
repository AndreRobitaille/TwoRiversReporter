namespace :rosters do
  desc "Preview canonical website roster changes (set APPLY=1 to persist)"
  task sync: :environment do
    dry_run = ENV["APPLY"] != "1"
    snapshots = CanonicalRosters::Registry.fetch
    result = CanonicalRosters::Synchronizer.new(snapshots: snapshots, dry_run: dry_run).call

    puts(dry_run ? "DRY RUN — no changes will be made" : "Applying canonical roster changes...")
    result.changes.each do |change|
      puts "#{change.action}: #{change.subject} (#{change.details})"
    end
    puts "No roster changes found." unless result.changed?
    puts "\n#{result.changes.size} change(s)#{dry_run ? "; run with APPLY=1 after reviewing" : " applied"}."
  end

  desc "Preview known attendance corrections (set APPLY=1 to persist)"
  task repair_known_misclassifications: :environment do
    dry_run = ENV["APPLY"] != "1"
    result = CanonicalRosters::KnownCorrections.new(dry_run: dry_run).call

    puts(dry_run ? "DRY RUN — no changes will be made" : "Applying known corrections...")
    result.changes.each do |change|
      puts "#{change.action}: #{change.subject} (#{change.details})"
    end
    puts "No known misclassifications found." unless result.changed?
    puts "\n#{result.changes.size} change(s)#{dry_run ? "; run with APPLY=1 after reviewing" : " applied"}."
  end

  desc "Preview the complete source-backed roster repair (set APPLY=1 to persist)"
  task repair: :environment do
    dry_run = ENV["APPLY"] != "1"
    snapshots = CanonicalRosters::Registry.fetch
    roster_result = nil
    correction_result = nil
    reconciliation_results = {}

    ActiveRecord::Base.transaction do
      roster_result = CanonicalRosters::Synchronizer.new(snapshots: snapshots, dry_run: false).call
      correction_result = CanonicalRosters::KnownCorrections.new(dry_run: false).call
      Committee.order(:name).each do |committee|
        result = Committees::MembershipReconciler.call(committee, dry_run: false)
        reconciliation_results[committee.name] = result if result.changed?
      end

      raise ActiveRecord::Rollback if dry_run
    end

    puts(dry_run ? "DRY RUN — no changes will be made" : "Applied source-backed roster repair.")
    roster_result.changes.each do |change|
      puts "#{change.action}: #{change.subject} (#{change.details})"
    end
    correction_result.changes.each do |change|
      puts "#{change.action}: #{change.subject} (#{change.details})"
    end
    reconciliation_results.each do |committee_name, result|
      puts "#{committee_name}: #{result.created} created, #{result.roles_updated} roles updated, #{result.ended} ended"
    end

    reconciliation_change_count = reconciliation_results.values.sum do |result|
      result.created + result.roles_updated + result.ended
    end
    total = roster_result.changes.size + correction_result.changes.size + reconciliation_change_count
    puts "No roster changes found." if total.zero?
    puts "\n#{total} reported change(s)#{dry_run ? "; run with APPLY=1 after reviewing" : " applied"}."
  end
end
