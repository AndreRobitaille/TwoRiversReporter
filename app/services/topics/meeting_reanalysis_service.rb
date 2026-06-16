module Topics
  class MeetingReanalysisService
    Result = Struct.new(
      :meeting,
      :before_topic_ids,
      :after_topic_ids,
      :affected_topic_ids,
      :selector_ids,
      :wire_ids,
      keyword_init: true
    )

    def initialize(meeting_id, allow_empty_topics: ENV["ALLOW_EMPTY_TOPICS"] == "1")
      @meeting_id = meeting_id
      @allow_empty_topics = allow_empty_topics
    end

    def call
      meeting = Meeting.find(@meeting_id)
      items = meeting.agenda_items.substantive.order(:order_index)
      item_ids = items.select(:id)

      before_topic_ids = AgendaItemTopic.where(agenda_item_id: item_ids).distinct.pluck(:topic_id).sort
      before_link_pairs = AgendaItemTopic.where(agenda_item_id: item_ids).pluck(:agenda_item_id, :topic_id)
      puts "Before topic ids: #{before_topic_ids.inspect}"

      after_topic_ids, after_link_pairs = rerun_extraction_with_rollback!(meeting, item_ids, before_link_pairs, before_topic_ids)

      affected_topic_ids = Array(before_topic_ids + after_topic_ids).uniq.sort
      puts "After topic ids: #{after_topic_ids.inspect}"
      puts "Affected topic ids: #{affected_topic_ids.inspect}"

      removed_link_pairs = before_link_pairs - after_link_pairs
      removed_appearance_ids = remove_stale_topic_links!(meeting, removed_link_pairs)
      removed_topic_ids = before_topic_ids - after_topic_ids
      remove_stale_topic_summaries!(meeting, removed_topic_ids)
      remove_stale_topic_status_events!(removed_link_pairs, removed_appearance_ids)
      regenerate_topic_summaries(meeting, after_topic_ids)
      regenerate_continuity(affected_topic_ids)
      regenerate_briefings(meeting, affected_topic_ids)

      selector_ids = homepage_selector_ids
      wire_ids = homepage_wire_ids

      Result.new(
        meeting: meeting,
        before_topic_ids: before_topic_ids,
        after_topic_ids: after_topic_ids,
        affected_topic_ids: affected_topic_ids,
        selector_ids: selector_ids,
        wire_ids: wire_ids
      )
    end

    private

    def remove_stale_topic_links!(meeting, removed_link_pairs)
      return [] if removed_link_pairs.empty?

      removed_appearance_ids = []

      removed_link_pairs.each_slice(1000) do |pairs|
        pairs.each do |agenda_item_id, topic_id|
          removed_appearance_ids.concat(TopicAppearance.where(meeting: meeting, agenda_item_id: agenda_item_id, topic_id: topic_id).pluck(:id))
          AgendaItemTopic.where(agenda_item_id: agenda_item_id, topic_id: topic_id).destroy_all
        end
      end

      TopicAppearance.where(id: removed_appearance_ids).destroy_all
      removed_appearance_ids
    end

    def rerun_extraction_with_rollback!(meeting, item_ids, before_links, before_topic_ids)
      AgendaItemTopic.where(agenda_item_id: item_ids).destroy_all
      ExtractTopicsJob.perform_now(meeting.id)

      status = meeting.reload.processing_state["topics_extraction_status"]
      raise "Topic extraction failed for Meeting #{meeting.id} (status=#{status.inspect})" if status == "parse_error"

      after_link_pairs = AgendaItemTopic.where(agenda_item_id: item_ids).pluck(:agenda_item_id, :topic_id)
      after_topic_ids = after_link_pairs.map(&:last).uniq.sort
      raise "Empty topic set for Meeting #{meeting.id}" if before_topic_ids.any? && after_topic_ids.empty? && !@allow_empty_topics

      [ after_topic_ids, after_link_pairs ]
    rescue => e
      current_link_pairs = AgendaItemTopic.where(agenda_item_id: item_ids).pluck(:agenda_item_id, :topic_id)
      partial_new_link_pairs = current_link_pairs - before_links
      remove_partial_topic_appearances!(meeting, partial_new_link_pairs)
      AgendaItemTopic.where(agenda_item_id: item_ids).destroy_all
      restore_before_links!(before_links)
      raise e
    end

    def remove_partial_topic_appearances!(meeting, partial_new_link_pairs)
      return if partial_new_link_pairs.empty?

      partial_new_link_pairs.each do |agenda_item_id, topic_id|
        TopicAppearance.where(meeting: meeting, agenda_item_id: agenda_item_id, topic_id: topic_id).destroy_all
      end
    end

    def restore_before_links!(before_links)
      rows = before_links.map do |agenda_item_id, topic_id|
        { agenda_item_id: agenda_item_id, topic_id: topic_id, created_at: Time.current, updated_at: Time.current }
      end
      AgendaItemTopic.insert_all(rows) if rows.any?
    end

    def remove_stale_topic_summaries!(meeting, removed_topic_ids)
      TopicSummary.where(meeting: meeting, topic_id: removed_topic_ids, summary_type: "topic_digest").destroy_all
    end

    def remove_stale_topic_status_events!(removed_link_pairs, stale_appearance_ids)
      return if removed_link_pairs.empty? || stale_appearance_ids.empty?

      removed_topic_ids = removed_link_pairs.map(&:last).uniq

      TopicStatusEvent.where(topic_id: removed_topic_ids).find_each do |event|
        source_ref = event.source_ref
        next unless source_ref.is_a?(Hash)

        appearance_id = source_ref["appearance_id"] || source_ref[:appearance_id]
        next unless stale_appearance_ids.include?(appearance_id)

        event.destroy!
      end
    end

    def regenerate_topic_summaries(meeting, after_topic_ids)
      ai_service = Ai::OpenAiService.new
      retrieval_service = RetrievalService.new

      Topic.approved.where(id: after_topic_ids).find_each do |topic|
        query = Topics::RetrievalQueryBuilder.new(topic, meeting).build_query
        chunks = retrieval_service.retrieve_topic_context(topic: topic, query_text: query, limit: 5, max_chars: 6000)
        formatted_context = retrieval_service.format_topic_context(chunks)
        context_json = Topics::SummaryContextBuilder.new(topic, meeting).build_context_json(kb_context_chunks: formatted_context)
        analysis_json_str = ai_service.analyze_topic_summary(context_json, source: topic)
        analysis_json = JSON.parse(analysis_json_str)
        markdown = ai_service.render_topic_summary(analysis_json.to_json, source: topic)

        summary = TopicSummary.find_or_initialize_by(topic: topic, meeting: meeting, summary_type: "topic_digest")
        summary.content = markdown
        summary.generation_data = analysis_json
        summary.save!

        impact = analysis_json["resident_impact"]
        score = impact["score"].to_i if impact.is_a?(Hash)
        topic.update_resident_impact_from_ai(score) if score&.between?(1, 5)
      end
    end

    def regenerate_continuity(topic_ids)
      topic_ids.each { |topic_id| Topics::UpdateContinuityJob.perform_now(topic_id: topic_id) }
    end

    def regenerate_briefings(meeting, topic_ids)
      topic_ids.each { |topic_id| Topics::GenerateTopicBriefingJob.perform_now(topic_id: topic_id, meeting_id: meeting.id) }
    end

    def homepage_selector_ids
      selector_result = GeneratedImages::HomepageTopicSelector.new
      selector_topics = selector_result.respond_to?(:call) ? selector_result.call : selector_result
      selector_ids = Array(selector_topics).map(&:id)
      puts "Homepage top story candidate ids: #{selector_ids.inspect}"
      selector_ids
    end

    def homepage_wire_ids
      wire_ids = Topic.reusable
        .where("resident_impact_score >= ?", HomeController::WIRE_MIN_IMPACT)
        .where("last_activity_at > ?", HomeController::ACTIVITY_WINDOW.ago)
        .order(resident_impact_score: :desc, last_activity_at: :desc, id: :desc)
        .limit(HomeController::WIRE_CARD_COUNT + HomeController::WIRE_ROW_LIMIT)
        .pluck(:id)

      puts "Homepage wire candidate ids: #{wire_ids.inspect}"
      puts "Topic 189 on homepage: #{(wire_ids | homepage_selector_ids).include?(189)}"
      wire_ids
    end
  end
end
