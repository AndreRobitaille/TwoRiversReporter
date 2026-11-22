require "digest"

module Meetings
  # The exact structured context consumed by meeting analysis, with retained
  # publication/source provenance. This is not approval of extracted facts.
  class MotionContext
    VERSION = 1
    attr_reader :meeting, :text, :manifest

    def self.capture(meeting_id)
      SummaryPublication.with_lock(meeting_id) { new(Meeting.find(meeting_id)) }
    end

    def self.current?(manifest, meeting:)
      return true if manifest.nil? # Older summaries have unknown dependencies.

      new(meeting).matches?(manifest)
    end

    def matches?(retained)
      return false unless retained.is_a?(Hash) && retained["version"] == VERSION && retained["source_catalog"].is_a?(Array)

      fields = %w[version meeting_id meeting_context status context_sha256]
      retained.slice(*fields) == manifest.slice(*fields) && Topics::GenerationEvidence.sources_current?(retained["source_catalog"])
    end

    def initialize(meeting)
      @meeting = meeting
      publication = meeting.minutes_publication
      pending = meeting.minutes_extractions.exists? && !Minutes::Publish.current?(meeting)
      @text = pending ? "Structured motion extraction is pending for the current minutes." : rendered_motions
      publication = nil if pending
      status = if pending
        "pending"
      elsif publication
        "published_extraction"
      else
        "legacy_projection"
      end
      @manifest = {
        "version" => VERSION, "meeting_id" => meeting.id,
        "meeting_context" => { "body_name" => meeting.body_name, "starts_at" => meeting.starts_at&.utc&.iso8601(6), "committee_id" => meeting.committee_id },
        "status" => status,
        "context_sha256" => Digest::SHA256.hexdigest(text),
        "publication_id" => publication&.id, "votes_extraction_id" => publication&.votes_extraction_id,
        "source_catalog" => publication ? [ publication.votes_extraction.input_manifest.fetch("source") ] : []
      }
    end

    private

    def rendered_motions
      motions = meeting.motions.includes(:agenda_item, :votes).order(:id).to_a
      return "No structured motion extraction available." if motions.empty?

      lines = motions.map do |motion|
        item = motion.agenda_item&.title || "No linked agenda item"
        vote_counts = motion.votes.group_by(&:value).transform_values(&:count)
        vote_text = vote_counts.any? ? vote_counts.sort.map { |value, count| "#{value}=#{count}" }.join(", ") : "no individual votes recorded"
        "- #{item}: #{motion.outcome} — #{motion.description} (#{vote_text})"
      end
      <<~TEXT.strip
        Structured motions extracted from the same meeting minutes. Use this as grounding for item decision and vote fields when it conflicts with noisy prose in the minutes.
        #{lines.join("\n")}
      TEXT
    end
  end
end
