module Topics
  class TriageTool
    DEFAULT_MIN_CONFIDENCE = 0.85
    DEFAULT_SIMILARITY_THRESHOLD = 0.75
    DEFAULT_MAX_TOPICS = 200
    DEFAULT_AGENDA_ITEM_LIMIT = 5
    DEFAULT_LOG_PATH = Rails.root.join("log", "topic_triage.log").to_s

    PROCEDURAL_KEYWORDS = [
      "roberts rules",
      "call to order",
      "roll call",
      "adjourn",
      "agenda approval",
      "minutes",
      "proclamation",
      "pledge",
      "public comment",
      "consent agenda",
      "communications",
      "announcements"
    ].freeze

    def self.call(apply: false, dry_run: true, min_confidence: DEFAULT_MIN_CONFIDENCE, max_topics: DEFAULT_MAX_TOPICS,
                  similarity_threshold: DEFAULT_SIMILARITY_THRESHOLD, agenda_item_limit: DEFAULT_AGENDA_ITEM_LIMIT,
                  user_id: nil, user_email: nil)
      new(
        apply: apply,
        dry_run: dry_run,
        min_confidence: min_confidence,
        max_topics: max_topics,
        similarity_threshold: similarity_threshold,
        agenda_item_limit: agenda_item_limit,
        user_id: user_id,
        user_email: user_email
      ).call
    end

    def initialize(apply:, dry_run:, min_confidence:, max_topics:, similarity_threshold:, agenda_item_limit:, user_id:, user_email:)
      @apply = apply
      @dry_run = dry_run
      @min_confidence = min_confidence
      @max_topics = max_topics
      @similarity_threshold = similarity_threshold
      @agenda_item_limit = agenda_item_limit
      @user_id = user_id
      @user_email = user_email
      @log_path = DEFAULT_LOG_PATH
    end

    def call
      context = build_context
      response = ::Ai::OpenAiService.new.triage_topics(context)
      if response.blank?
        raise "Topic triage returned empty response"
      end

      results = JSON.parse(response)

      report_results(results)
      return results unless apply_changes?

      user = resolve_user
      apply_results(results, user)
      results
    rescue JSON::ParserError => e
      Rails.logger.error("Topic triage failed to parse JSON: #{e.message}")
      raise
    end

    private

    def apply_changes?
      @apply && !@dry_run
    end

    def build_context
      topics = Topic.where(status: "proposed")
                    .order(last_activity_at: :desc)
                    .limit(@max_topics)
                    .includes(:agenda_items)

      topic_payloads = topics.map do |topic|
        agenda_items = topic.agenda_items.first(@agenda_item_limit)
        {
          id: topic.id,
          name: topic.name,
          canonical_name: topic.canonical_name,
          lifecycle_status: topic.lifecycle_status,
          status: topic.status,
          last_activity_at: topic.last_activity_at&.iso8601,
          agenda_items: agenda_items.map { |item| { id: item.id, title: item.title, summary: item.summary } }
        }
      end

      similarity_candidates = build_similarity_candidates(topics)

      {
        procedural_keywords: PROCEDURAL_KEYWORDS,
        similarity_threshold: @similarity_threshold,
        topics: topic_payloads,
        similarity_candidates: similarity_candidates
      }
    end

    def build_similarity_candidates(topics)
      candidates = []

      topics.each do |topic|
        similar = Topic.similar_to(topic.name, @similarity_threshold)
                       .where.not(id: topic.id)
                       .limit(8)
                       .pluck(:id, :name)

        next if similar.empty?

        candidates << {
          topic_id: topic.id,
          topic_name: topic.name,
          similar: similar.map { |id, name| { id: id, name: name } }
        }
      end

      candidates
    end

    def resolve_user
      if @user_id
        User.find_by(id: @user_id)
      elsif @user_email
        User.find_by(email_address: @user_email)
      else
        nil
      end
    end

    def report_results(results)
      merges = Array(results["merge_map"])
      approvals = Array(results["approvals"])
      blocks = Array(results["blocks"])

      Rails.logger.info("Topic triage suggestions: #{merges.size} merges, #{approvals.size} approvals, #{blocks.size} blocks")
      append_log("suggestions merges=#{merges.size} approvals=#{approvals.size} blocks=#{blocks.size}")
    end

    def apply_results(results, user)
      apply_merges(Array(results["merge_map"]), user)
      apply_approvals(Array(results["approvals"]), user)
      apply_blocks(Array(results["blocks"]), user)
    end

    def apply_merges(merges, user)
      merges.each do |merge|
        confidence = merge["confidence"].to_f
        next if confidence < @min_confidence

        canonical = merge["canonical"].to_s
        aliases = Array(merge["aliases"])
        next if canonical.blank? || aliases.empty?

        target_topic = Topic.find_by(name: Topic.normalize_name(canonical))
        next unless target_topic

        aliases.each do |alias_name|
          source_topic = Topic.find_by(name: Topic.normalize_name(alias_name))
          next unless source_topic
          next if source_topic.id == target_topic.id

          merge_topics!(source_topic, target_topic)
          record_review_event(user, target_topic, "merged", merge_reason(merge))
          append_log("merge source=#{source_topic.id} target=#{target_topic.id} confidence=#{confidence} rationale=#{merge["rationale"]}")
        end
      end
    end

    def apply_approvals(approvals, user)
      approvals.each do |approval|
        confidence = approval["confidence"].to_f
        next if confidence < @min_confidence

        topic_name = approval["topic"].to_s
        next if topic_name.blank?

        topic = Topic.find_by(name: Topic.normalize_name(topic_name))
        next unless topic
        next if topic.status == "approved"

        topic.update!(status: "approved", review_status: "approved")
        record_review_event(user, topic, "approved", approval_reason(approval))
        append_log("approve topic=#{topic.id} confidence=#{confidence} rationale=#{approval["rationale"]}")
      end
    end

    def apply_blocks(blocks, user)
      blocks.each do |block|
        confidence = block["confidence"].to_f
        next if confidence < @min_confidence

        topic_name = block["topic"].to_s
        next if topic_name.blank?

        topic = Topic.find_by(name: Topic.normalize_name(topic_name))
        next unless topic
        next if topic.status == "blocked"

        topic.update!(status: "blocked", review_status: "blocked")
        record_review_event(user, topic, "blocked", block_reason(block))
        append_log("block topic=#{topic.id} confidence=#{confidence} rationale=#{block["rationale"]}")
      end
    end

    def merge_topics!(source_topic, target_topic)
      ActiveRecord::Base.transaction do
        TopicAlias.create!(topic: target_topic, name: source_topic.name)
        source_topic.topic_aliases.update_all(topic_id: target_topic.id)

        source_topic.agenda_item_topics.each do |agenda_item_topic|
          unless AgendaItemTopic.exists?(agenda_item: agenda_item_topic.agenda_item, topic: target_topic)
            agenda_item_topic.update!(topic: target_topic)
          else
            agenda_item_topic.destroy
          end
        end

        source_topic.destroy!
      end
    end

    def merge_reason(merge)
      base = "Auto-merge via triage tool"
      rationale = merge["rationale"].to_s
      rationale.present? ? "#{base}: #{rationale}" : base
    end

    def approval_reason(approval)
      base = "Auto-approve via triage tool"
      rationale = approval["rationale"].to_s
      rationale.present? ? "#{base}: #{rationale}" : base
    end

    def block_reason(block)
      base = "Auto-block via triage tool"
      rationale = block["rationale"].to_s
      rationale.present? ? "#{base}: #{rationale}" : base
    end

    def record_review_event(user, topic, action, reason)
      return unless user

      TopicReviewEvent.create!(
        topic: topic,
        user: user,
        action: action,
        reason: reason
      )
    end

    def append_log(message)
      timestamp = Time.current.utc.iso8601
      File.open(@log_path, "a") { |file| file.puts("#{timestamp} #{message}") }
    rescue => e
      Rails.logger.warn("Topic triage log write failed: #{e.message}")
    end
  end
end
