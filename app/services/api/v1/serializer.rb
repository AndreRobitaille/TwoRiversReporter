module Api
  module V1
    # Each field, including fields nested in generated JSON, is a deliberate
    # resident-content projection. Stored analysis is never returned wholesale.
    class Serializer
      include Rails.application.routes.url_helpers

      def initialize(base_url:)
        @base_url = base_url
        @canonical_meetings = {}
        @illustrations = {}
        @citation_resolvers = {}
        @helpers = ApplicationController.helpers
      end

      def url(path)
        "#{@base_url}#{path}"
      end

      def content_updates
        @content_updates ||= ContentUpdates.new
      end

      def topic(topic)
        { id: topic.id, name: topic.name, canonical_name: topic.canonical_name,
          description: topic.description, lifecycle: topic.lifecycle_status,
          resident_impact_score: topic.resident_impact_score,
          last_activity_at: timestamp(topic.last_activity_at),
          headline: topic.topic_briefing&.headline, links: { website: url(topic_path(topic)),
            api: url("/api/v1/topics/#{topic.id}") }, illustration: illustration(topic, :og) }.merge(update_metadata(topic))
      end

      def topic_detail(record)
        briefing = record.topic_briefing
        upcoming = record.topic_appearances.joins(:meeting).where("meetings.starts_at > ?", Time.current)
          .includes(:meeting, :agenda_item).order("meetings.starts_at ASC", id: :asc)
        result = topic(record)
        result.merge(briefing: briefing_payload(briefing), upcoming: upcoming.limit(10).map { |entry| appearance(entry) },
          upcoming_count: upcoming.count, appearance_count: record.topic_appearances.count,
          links: result[:links].merge(appearances: url("/api/v1/topics/#{record.id}/appearances"),
            decisions: url("/api/v1/topics/#{record.id}/decisions")))
      end

      def briefing_payload(briefing)
        return unless briefing

        { headline: briefing.headline, ai_generated: true, generated_at: timestamp(briefing.updated_at),
          tier: briefing.generation_tier, what_to_watch: string(@helpers.briefing_what_to_watch(briefing)),
          current_state: string(@helpers.briefing_current_state(briefing)),
          process_concerns: strings(@helpers.briefing_process_concerns(briefing)),
          timeline_count: Array(@helpers.briefing_factual_record(briefing)).size }
      end

      def appearance(entry)
        { kind: "agenda_appearance", id: entry.id, appeared_at: timestamp(entry.appeared_at),
          evidence_type: entry.evidence_type, meeting: meeting_reference(entry.meeting),
          agenda_item: entry.agenda_item ? { id: entry.agenda_item.id, title: entry.agenda_item.display_context_title } : nil }
      end

      def timeline(entry, index, record_meetings)
        entry = entry.is_a?(Hash) ? entry : {}
        safe = entry.slice("event", "date", "meeting").transform_values { |value| string(value) }
        enriched = @helpers.enrich_record_entry(safe, record_meetings)
        { kind: "timeline_event", index: index, date: safe["date"], event: enriched[:event],
          meeting_name: enriched[:meeting_name], meeting: enriched[:meeting] ? meeting_reference(enriched[:meeting]) : nil,
          ai_generated: true }
      end

      def canonical(meeting)
        @canonical_meetings[meeting.id] ||= Meeting.preferred_duplicate(meeting.identity_matches)
      end

      def remember_canonical(records)
        records.each { |record| @canonical_meetings[record.id] = record }
      end

      def preload_illustrations(records)
        return unless records.first.is_a?(Topic) || records.first.is_a?(Meeting)

        type = records.first.class.base_class.name
        surface = type == "Topic" ? :og : :feature
        records.each { |record| @illustrations[[ type, record.id, surface ]] = nil }
        GeneratedImage.usable_for(surface).where(imageable_type: type, imageable_id: records.map(&:id))
          .includes(file_attachment: :blob).each do |image|
            next unless image.file.attached?

            @illustrations[[ type, image.imageable_id, surface ]] ||= image
          end
      end

      def meeting_reference(record)
        record = canonical(record)
        { id: record.id, body: @helpers.clean_meeting_display(record.body_name), starts_at: timestamp(record.starts_at),
          cancelled: record.cancelled?, links: { website: url(meeting_path(record)), api: url("/api/v1/meetings/#{record.id}") } }
      end

      def meeting(record)
        reference = meeting_reference(record)
        reference.merge(location: record.location, committee: record.committee ? committee_reference(record.committee) : nil,
          cancellation_notice: record.cancellation_notice, summary: summary(record),
          source_url: external_url(record.detail_page_url), illustration: illustration(record, :feature),
          links: reference[:links].merge(
            agenda_items: url("/api/v1/meetings/#{record.id}/agenda_items"),
            documents: url("/api/v1/meetings/#{record.id}/documents"),
            transcript: url("/api/v1/meetings/#{record.id}/transcript"))).merge(update_metadata(record))
      end

      def meeting_detail(record, requested_id:)
        result = meeting(record)
        result.merge(requested_id: requested_id.to_i, canonical_id: record.id,
          topics: record.agenda_items.select(&:substantive?).flat_map(&:topics).uniq.select(&:approved?).map { |entry| topic(entry) },
          documents: resident_documents(record).map { |document| document_payload(document) })
      end

      def summary(meeting)
        summary = ResidentContent::MeetingSelection.preferred_summary(meeting)
        return unless summary

        data = summary.generation_data.is_a?(Hash) ? summary.generation_data : {}
        { id: summary.id, summary_type: summary.summary_type, ai_generated: true,
          source_type: string(data["source_type"]), generated_at: timestamp(summary.updated_at),
          headline: string(data["headline"]),
          highlights: hashes(data["highlights"]).map { |entry| {
            text: string(entry["text"]), vote: string(entry["vote"]), citations: citations(entry["citations"] || entry["citation"], summary: summary) } },
          public_input: hashes(data["public_input"]).map { |entry| {
            type: string(entry["type"]), speaker: string(entry["speaker"]),
            summary: string(entry["summary"])&.gsub(/\s*\[Address redacted\.?\]\s*/i, " ")&.strip,
            citations: citations(entry["citations"] || entry["citation"], summary: summary) } },
          legacy_markdown: data.empty? ? summary.content : nil,
          agenda_items_url: url("/api/v1/meetings/#{meeting.id}/agenda_items") }
      end

      def agenda_items(meeting)
        items = meeting.agenda_items.select(&:substantive?).sort_by { |item| [ item.order_index || 0, item.id ] }
        summary = ResidentContent::MeetingSelection.preferred_summary(meeting)
        details = hashes(summary&.generation_data&.dig("item_details"))
        matched_ids = []
        analyses = details.map do |entry|
          match = Topics::ItemDetailsMatcher.new(items, [ entry ]).build.keys.first
          item = items.find { |candidate| candidate.id == match }
          matched_ids << item.id if item
          item_payload(meeting, item, entry, summary: summary)
        end
        analyses + items.reject { |item| matched_ids.include?(item.id) }.map { |item| item_payload(meeting, item, {}, summary: summary) }
      end

      def item_payload(meeting, item, analysis, summary: nil)
        { agenda_item_id: item&.id, number: item&.number,
          title: string(analysis["agenda_item_title"]) || item&.display_context_title,
          planned_summary: item&.summary, recommended_action: item&.recommended_action,
          analysis: { summary: string(analysis["summary"]), decision: string(analysis["decision"]),
            vote: string(analysis["vote"]), public_hearing: string(analysis["public_hearing"]),
            citations: citations(analysis["citations"] || analysis["citation"], summary: summary), ai_generated: analysis.present? },
          topics: item ? item.topics.select(&:approved?).map { |record| topic(record) } : [],
          motions: item && !meeting.cancelled? ? item.motions.map { |motion| motion_payload(motion) } : [] }
      end

      def motion_payload(motion)
        { id: motion.id, description: motion.description, outcome: motion.outcome,
          meeting: meeting_reference(motion.meeting), agenda_item_id: motion.agenda_item_id,
          votes: motion.votes.map { |vote| { official_id: vote.member_id, name: vote.member.name, value: vote.value } } }
      end

      def resident_documents(meeting)
        meeting.latest_documents("agenda_pdf", "agenda_html", "packet_pdf", "packet_html", "minutes_pdf", "minutes_html", "transcript")
      end

      def document_payload(document)
        { id: document.id, type: document.document_type, source_url: external_url(document.source_url),
          official_record: document.document_type != "transcript", page_count: document.page_count,
          text_quality: document.text_quality, fetched_at: timestamp(document.fetched_at),
          created_at: document.created_at&.iso8601(6), updated_at: document.updated_at&.iso8601(6) }
      end

      def committee_reference(committee)
        { id: committee.id, slug: committee.slug, name: committee.name, type: committee.committee_type,
          status: committee.status, links: { website: url(committee_path(committee.slug)),
            api: url("/api/v1/committees/#{committee.slug}") } }
      end

      def committee_detail(committee)
        memberships = ResidentContent::CommitteeDirectory.new.public_memberships(committee)
        topics = Topic.publicly_visible.joins(agenda_item_topics: { agenda_item: :meeting })
          .where(meetings: { committee_id: committee.id }).select("topics.*, MAX(meetings.starts_at) AS latest_meeting_date")
          .group("topics.id").includes(:topic_briefing)
          .order(Arel.sql("topics.resident_impact_score DESC NULLS LAST, latest_meeting_date DESC, topics.id DESC")).limit(7)
        committee_reference(committee).merge(description: committee.description,
          roster: memberships.map { |membership| membership_payload(membership).merge(official: official(membership.member)) },
          recent_topics: topics.map { |entry| topic(entry) },
          meetings_url: url("/api/v1/meetings?committee_id=#{committee.id}"))
      end

      def membership_payload(membership)
        { committee: committee_reference(membership.committee), role: membership.role,
          title: membership.position_title, started_on: membership.started_on&.iso8601,
          source: membership.source, source_url: external_url(membership.source_url),
          verified_at: timestamp(membership.verified_at) }
      end

      def official(member)
        { id: member.id, name: member.name, current_title: member.primary_current_position&.title,
          links: { website: url(member_path(member)), api: url("/api/v1/officials/#{member.id}") } }
      end

      def official_detail(member)
        profile = ResidentContent::OfficialProfile.new(member)
        memberships = member.committee_memberships.select { |membership|
          membership.ended_on.nil? && !%w[staff non_voting].include?(membership.role)
        }.sort_by { |membership| [ membership.committee.name == "City Council" ? 0 : 1, membership.committee.name ] }
        official(member).merge(positions: member.current_member_positions.map { |position| {
          title: position.title, source: position.source, source_url: external_url(position.source_url),
          verified_at: timestamp(position.verified_at) } },
          memberships: memberships.map { |membership| membership_payload(membership) },
          attendance: Array(profile.attendance).map { |committee, data| {
            committee: committee_reference(committee), total: data[:total], present: data[:present],
            percentage: data[:pct], peer_percentage: data[:avg_rate] } },
          votes_url: url("/api/v1/officials/#{member.id}/votes"))
      end

      def vote_payload(vote)
        { id: vote.id, value: vote.value, motion: motion_payload(vote.motion),
          topics: vote.motion.agenda_item ? vote.motion.agenda_item.topics.select(&:approved?).map { |entry| topic(entry) } : [] }
      end

      def timestamp(time)
        time&.iso8601
      end

      private

        def update_metadata(record)
          content_updates.for(record).transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601(6) : value }
        end

        def illustration(record, surface)
          key = [ record.class.base_class.name, record.id, surface ]
          @illustrations[key] = record.current_generated_image(surface) unless @illustrations.key?(key)
          image = @illustrations[key]
          return unless image&.file&.attached?

          { url: url(rails_blob_path(image.file, only_path: true)),
            alt: "Illustration for #{record.respond_to?(:name) ? record.name : record.body_name}", illustrative: true }
        end

        def citations(value, summary:)
          return [] unless summary

          resolver = @citation_resolvers[summary.id] ||= Citations::Resolver.for_summary(summary)
          resolver.resolve_all(value)
        end

        def string(value)
          value if value.is_a?(String)
        end

        def strings(value)
          Array(value).filter_map { |entry| string(entry) }
        end

        def hashes(value)
          Array(value).select { |entry| entry.is_a?(Hash) }
        end

        def external_url(value)
          uri = URI.parse(value.to_s)
          value if uri.is_a?(URI::HTTP) && uri.host.present? && uri.userinfo.nil?
        rescue URI::InvalidURIError
          nil
        end
    end
  end
end
