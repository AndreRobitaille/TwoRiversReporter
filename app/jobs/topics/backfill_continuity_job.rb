class Topics::BackfillContinuityJob < ApplicationJob
  queue_as :default

  def perform(topic_id = nil)
    if topic_id
      backfill_topic(Topic.find(topic_id))
    else
      Topic.find_each do |topic|
        backfill_topic(topic)
      rescue => e
        Rails.logger.error "Failed to backfill topic #{topic.id}: #{e.message}"
      end
    end
  end

  private

  def backfill_topic(topic)
    Rails.logger.info "Backfilling topic #{topic.id}: #{topic.name}"

    # 1. Normalize name and handle canonical_name uniqueness
    base_canonical = Topic.normalize_name(topic.name)
    if base_canonical.blank?
      # Fallback for empty names (shouldn't happen due to validations)
      base_canonical = "topic-#{topic.id}"
    end

    canonical = base_canonical
    counter = 1
    while Topic.where(canonical_name: canonical).where.not(id: topic.id).exists?
      canonical = "#{base_canonical} #{counter}"
      counter += 1
    end
    topic.canonical_name = canonical

    # 2. Create slug
    base_slug = topic.canonical_name.parameterize
    slug = base_slug
    counter = 1
    while Topic.where(slug: slug).where.not(id: topic.id).exists?
      slug = "#{base_slug}-#{counter}"
      counter += 1
    end
    topic.slug = slug

    # 3. Sync review_status
    topic.review_status ||= topic.status

    # Save base changes before continuity processing
    if topic.save
      Rails.logger.info "Updated base fields for topic #{topic.id}"
    else
      Rails.logger.error "Failed to save topic #{topic.id}: #{topic.errors.full_messages}"
      return
    end

    # 4. Rebuild topic_appearances
    # Find associated agenda_items via agenda_item_topics
    # We destroy existing ones to ensure idempotency
    topic.topic_appearances.destroy_all

    topic.agenda_items.includes(:meeting).each do |ai|
      meeting = ai.meeting
      next unless meeting

      topic.topic_appearances.create!(
        meeting: meeting,
        agenda_item: ai,
        appeared_at: meeting.starts_at || ai.created_at,
        body_name: meeting.body_name,
        evidence_type: "agenda_item",
        source_ref: { agenda_item_id: ai.id, number: ai.number, title: ai.title }
      )
    end

    # 5. Update timestamps and lifecycle status via service
    Topics::ContinuityService.call(topic)

    Rails.logger.info "Successfully backfilled continuity for topic #{topic.id}"
  end
end
