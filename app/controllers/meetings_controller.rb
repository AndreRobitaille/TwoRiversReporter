class MeetingsController < ApplicationController
  UPCOMING_WINDOW = 21.days
  RECENT_WINDOW = 21.days

  def index
    upcoming_all = Meeting
      .where(starts_at: Time.current..UPCOMING_WINDOW.from_now)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :asc)

    # Split upcoming: enriched (has agenda/topics) vs thin (just scheduled)
    @upcoming_enriched, @upcoming_thin = deduplicate_meetings(upcoming_all, :upcoming).partition { |m| meeting_has_content?(m, :upcoming) }

    recent_all = Meeting
      .where(starts_at: (RECENT_WINDOW.ago)..Time.current)
      .includes(:committee, :meeting_documents, :meeting_summaries, agenda_items: :topics)
      .order(starts_at: :desc)

    # Split recent: enriched (has summary) vs thin (no summary)
    @recent_enriched, @recent_thin = deduplicate_meetings(recent_all, :recent).partition { |m| meeting_has_content?(m, :recent) }

    if params[:q].present?
      @pagy, @search_results = pagy(:offset, Meeting.search_multi(params[:q]), limit: 15)
    end
  end

  def show
    @meeting = Meeting.find(params[:id])
    @meeting_display_name = helpers.clean_meeting_display(@meeting.body_name).presence || "Meeting"
    @generated_image = @meeting.current_generated_image(:feature)
    assign_generated_image_meta(@generated_image, alt: "Illustration for #{@meeting_display_name}")

    substantive_item_ids = @meeting.agenda_items.substantive.select(:id)
    approved_topics = Topic.approved
      .joins(:agenda_item_topics)
      .where(agenda_item_topics: { agenda_item_id: substantive_item_ids })
      .includes(:topic_briefing, topic_appearances: :agenda_item)
      .distinct

    @ongoing_topics, @new_topics = approved_topics.partition do |topic|
      topic.topic_appearances.count { |appearance| appearance.agenda_item.nil? || appearance.agenda_item.substantive? } > 1
    end

    @has_substantive_agenda_content = @meeting.agenda_items.any?(&:substantive?) || @meeting.meeting_summaries.any?
    @has_substantive_topic_content = approved_topics.any?

    # Supersede chain: minutes > transcript > packet > agenda preview.
    @summary = preferred_meeting_summary(@meeting)
  end

  private

  def deduplicate_meetings(meetings, zone)
    meetings.group_by(&:duplicate_identity_key)
      .values
      .map { |duplicates| preferred_duplicate(duplicates, zone) }
  end

  def preferred_duplicate(duplicates, zone)
    duplicates.max_by do |meeting|
      [
        cancelled_meeting?(meeting) ? 0 : 1,
        meeting_has_content?(meeting, zone) ? 1 : 0,
        meeting.updated_at.to_i,
        -meeting.id
      ]
    end
  end

  def cancelled_meeting?(meeting)
    meeting.body_name.to_s.match?(/\b(cancelled|canceled)\b/i)
  end

  def meeting_has_content?(meeting, zone)
    case zone
    when :upcoming
      topics = meeting.agenda_items.select(&:substantive?).flat_map(&:topics).uniq.select(&:approved?)
      topics.any? || meeting.meeting_summaries.any? || meeting.document_status.in?([ :agenda, :packet, :minutes ])
    when :recent
      meeting.meeting_summaries.any?
    end
  end

  def preferred_meeting_summary(meeting)
    meeting.meeting_summaries
      .to_a
      .select { |summary| summary_usable?(summary) }
      .min_by { |summary| [ summary_priority(summary), -(summary.updated_at || summary.created_at || Time.at(0)).to_i ] }
  end

  def assign_generated_image_meta(image, alt:)
    return unless image&.file&.attached?

    @page_og_image = generated_image_url(image.file)
    @page_og_image_alt = alt
    @page_og_image_width = 1536
    @page_og_image_height = 1024
  end

  def generated_image_url(attachment)
    if Rails.env.production?
      rails_blob_url(attachment, host: MeetingsHelper::PRODUCTION_HOST, protocol: "https")
    else
      rails_blob_url(attachment, host: request.host_with_port, protocol: request.protocol.delete_suffix("://"))
    end
  end

  def summary_usable?(summary)
    summary.content.present? || summary.generation_data.present?
  end

  def summary_priority(summary)
    MeetingsHelper::SUMMARY_TYPE_PRIORITY.index(summary.summary_type) || 99
  end
end
