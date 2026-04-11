# lib/tasks/headline_voice.rake
#
# One-off rake tasks supporting the homepage headline voice prompt rewrite.
# See docs/superpowers/specs/2026-04-10-homepage-headline-voice-design.md.
#
# Usage (on prod via kamal):
#   bin/kamal app exec "bin/rails headline_voice:backfill"
#   bin/kamal app exec "bin/rails headline_voice:verify"

namespace :headline_voice do
  desc "Regenerate TopicBriefings for homepage-eligible topics (impact >= 2, last 30 days)"
  task backfill: :environment do
    topics = Topic.approved
      .where("resident_impact_score >= ?", 2)
      .where("last_activity_at > ?", 30.days.ago)
      .order(resident_impact_score: :desc, last_activity_at: :desc)
      .to_a

    puts "Backfilling #{topics.size} topics..."
    puts ""

    succeeded = 0
    failed = []

    topics.each_with_index do |topic, i|
      meeting = topic.topic_appearances
        .joins(:meeting)
        .order("meetings.starts_at DESC")
        .first&.meeting

      if meeting.nil?
        puts "[#{i + 1}/#{topics.size}] SKIP: #{topic.name} (no meeting)"
        next
      end

      print "[#{i + 1}/#{topics.size}] #{topic.name} (impact=#{topic.resident_impact_score})... "
      $stdout.flush
      start = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      begin
        Topics::GenerateTopicBriefingJob.perform_now(
          topic_id: topic.id,
          meeting_id: meeting.id
        )
        duration = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
        puts "OK (#{duration.round(1)}s)"
        succeeded += 1
      rescue => e
        puts "FAILED: #{e.class}: #{e.message}"
        failed << { topic: topic.name, error: "#{e.class}: #{e.message}" }
      end
    end

    puts ""
    puts "Done. #{succeeded}/#{topics.size} succeeded."
    if failed.any?
      puts ""
      puts "Failures:"
      failed.each { |f| puts "  - #{f[:topic]}: #{f[:error]}" }
    end
  end

  desc "Verify homepage headline voice success criteria on current briefings"
  task verify: :environment do
    banned_closers = [
      "no vote has been reported yet",
      "vote unclear",
      "still pending",
      "still no clear decision",
      "keeps coming back",
      "keep coming back",
      "keeps coming up",
      "keep coming up",
      "keeps circling",
      "keeps popping up",
      "keep showing up",
      "keeps showing up",
      "contract execution concerns",
      "discussion expected",
      "stayed high-level",
      "remained high-level",
      "stayed vague",
      "stayed general",
      "still not clear",
      "hasn't been spelled out"
    ].freeze

    untranslated_jargon = [
      /\bTID\b/,
      /\bT\.I\.D\.\b/i,
      /\bsaw-cut/i,
      /\brevenue bond/i,
      /\benterprise fund/i,
      /\bconditional use permit/i,
      /\bcertified survey map/i,
      /\bgeneral obligation promissory note/i,
      /\bCIPP\b/,
      /\bcured in place pipe/i
    ].freeze

    # A headline "leads with a concrete detail" if its first 40 characters
    # contain a dollar amount, a year, an ordinal street, a percentage,
    # a known street name, a named council action, or a month abbreviation.
    concrete_lead_patterns = [
      /\$[\d,.]+/,
      /\b20\d\d\b/,
      /\b\d+(?:st|nd|rd|th)\b/i,
      /\b\d+%/,
      /\b(?:Lincoln|Washington|Main|Memorial|Forest|Twin)/i,
      /\bCouncil\s+(?:votes|picks)/i,
      /\b(?:Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec|Jan|Feb|Mar)\b/
    ].freeze

    topics = Topic.approved
      .where("resident_impact_score >= ?", 2)
      .where("last_activity_at > ?", 30.days.ago)
      .includes(:topic_briefing)
      .to_a

    puts "Verifying #{topics.size} homepage-eligible topics..."
    puts ""

    violations = {
      banned_closer: [],
      jargon: [],
      no_concrete_lead: [],
      missing_briefing: [],
      missing_headline: []
    }

    topics.each do |topic|
      briefing = topic.topic_briefing
      if briefing.nil?
        violations[:missing_briefing] << topic.name
        next
      end
      headline = briefing.headline.to_s
      if headline.empty?
        violations[:missing_headline] << topic.name
        next
      end

      banned_closers.each do |phrase|
        if headline.downcase.include?(phrase)
          violations[:banned_closer] << { topic: topic.name, headline: headline, phrase: phrase }
        end
      end

      untranslated_jargon.each do |pattern|
        if headline.match?(pattern)
          violations[:jargon] << { topic: topic.name, headline: headline, match: headline.match(pattern)[0] }
        end
      end

      lead = headline[0, 40]
      unless concrete_lead_patterns.any? { |p| lead.match?(p) }
        violations[:no_concrete_lead] << { topic: topic.name, headline: headline }
      end
    end

    puts "=== Criterion 1: No banned closers ==="
    if violations[:banned_closer].empty?
      puts "  PASS - 0/#{topics.size} headlines contain banned closers"
    else
      puts "  FAIL - #{violations[:banned_closer].size} headlines contain banned closers:"
      violations[:banned_closer].each do |v|
        puts "    #{v[:topic]}: \"#{v[:headline]}\" (banned: #{v[:phrase]})"
      end
    end
    puts ""

    puts "=== Criterion 2 & 3: No untranslated jargon ==="
    if violations[:jargon].empty?
      puts "  PASS - 0/#{topics.size} headlines contain untranslated jargon"
    else
      puts "  FAIL - #{violations[:jargon].size} headlines contain untranslated jargon:"
      violations[:jargon].each do |v|
        puts "    #{v[:topic]}: \"#{v[:headline]}\" (match: #{v[:match]})"
      end
    end
    puts ""

    concrete_count = topics.size - violations[:no_concrete_lead].size - violations[:missing_briefing].size - violations[:missing_headline].size
    threshold = (topics.size * 2.0 / 3).ceil
    puts "=== Criterion 4: At least 2/3 of headlines lead with a concrete detail ==="
    puts "  Concrete leads: #{concrete_count}/#{topics.size}"
    puts "  Threshold: #{threshold}"
    if concrete_count >= threshold
      puts "  PASS"
    else
      puts "  FAIL - below #{threshold} threshold. Headlines without concrete leads:"
      violations[:no_concrete_lead].first(10).each { |v| puts "    #{v[:topic]}: \"#{v[:headline]}\"" }
    end
    puts ""

    puts "=== Criterion 5: MANUAL REVIEW - 5 random briefings for bleed check ==="
    puts "  Read each sample below and confirm factual_record, civic_sentiment,"
    puts "  pattern_observations, and process_concerns read as dry / observational."
    puts "  Any editorial voice, manufactured drama, or loaded language in these"
    puts "  fields is a bleed failure."
    puts ""

    sample = topics.reject { |t| t.topic_briefing.nil? }.sample(5)
    sample.each_with_index do |topic, i|
      gd = topic.topic_briefing.generation_data || {}
      puts "  [#{i + 1}] #{topic.name}"
      puts "      headline: #{topic.topic_briefing.headline}"
      puts ""
      fr = (gd["factual_record"] || []).first(2)
      puts "      factual_record (first 2):"
      fr.each { |e| puts "        - [#{e['date']}] #{e['event'].to_s[0, 200]}" }
      cs = (gd["civic_sentiment"] || []).first(2)
      puts "      civic_sentiment (first 2): #{cs.any? ? '' : '(empty)'}"
      cs.each { |e| puts "        - #{e['observation'].to_s[0, 200]}" }
      po = gd.dig("editorial_analysis", "pattern_observations") || []
      puts "      pattern_observations (#{po.size}):"
      po.first(2).each { |p| puts "        - #{p.to_s[0, 200]}" }
      pc = gd.dig("editorial_analysis", "process_concerns")
      puts "      process_concerns: #{pc.nil? ? '(null)' : pc.to_s[0, 300]}"
      puts ""
    end

    puts "=== Criterion 6: MANUAL REVIEW - fact-grounding spot check ==="
    puts "  For the highest-impact topic with a dollar amount in the headline,"
    puts "  verify the dollar amount appears in the topic's prior summaries or"
    puts "  recent meeting context. If the amount is nowhere in the source chain,"
    puts "  the model hallucinated and the prompt change must be reverted."
    puts ""

    dollar_topic = topics
      .reject { |t| t.topic_briefing.nil? }
      .select { |t| t.topic_briefing.headline.to_s.match?(/\$[\d,.]+/) }
      .max_by(&:resident_impact_score)

    if dollar_topic
      puts "  Topic: #{dollar_topic.name} (impact=#{dollar_topic.resident_impact_score})"
      puts "  Headline: #{dollar_topic.topic_briefing.headline}"
      amount_match = dollar_topic.topic_briefing.headline.match(/\$[\d,.]+(?:\s*(?:million|billion))?/i)
      amount = amount_match ? amount_match[0] : nil
      puts "  Amount to verify: #{amount.inspect}"
      puts ""
      puts "  Prior topic summaries (oldest to newest):"
      dollar_topic.topic_summaries.joins(:meeting).order("meetings.starts_at ASC").each do |ts|
        gd_str = ts.generation_data.to_json
        contains = amount && gd_str.include?(amount.gsub(/[\s,]/, "").gsub(/million|billion/i, ""))
        marker = contains ? "FOUND" : "     "
        puts "    #{marker} #{ts.meeting.body_name} #{ts.meeting.starts_at.to_date}"
      end
      puts ""
      puts "  If FOUND appears above, the amount is grounded. If not, manually"
      puts "  inspect the most recent meeting document for the amount."
    else
      puts "  No homepage-eligible topic has a dollar amount in its headline."
      puts "  Pick a different specific detail (street name, date) to spot-check manually."
    end

    puts ""
    puts "=" * 60
    auto_failed = violations[:banned_closer].any? ||
                  violations[:jargon].any? ||
                  (concrete_count < threshold) ||
                  violations[:missing_briefing].any? ||
                  violations[:missing_headline].any?

    if auto_failed
      puts "AUTOMATED CHECKS: FAIL"
      puts "Fix the violations above before proceeding."
      exit 1
    else
      puts "AUTOMATED CHECKS: PASS"
      puts "Now read the samples printed under Criteria 5 and 6 and confirm"
      puts "them manually before shipping."
    end
  end
end
