# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_18_031350) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agenda_item_documents", force: :cascade do |t|
    t.bigint "agenda_item_id", null: false
    t.datetime "created_at", null: false
    t.bigint "meeting_document_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agenda_item_id"], name: "index_agenda_item_documents_on_agenda_item_id"
    t.index ["meeting_document_id"], name: "index_agenda_item_documents_on_meeting_document_id"
  end

  create_table "agenda_item_topics", force: :cascade do |t|
    t.bigint "agenda_item_id", null: false
    t.datetime "created_at", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agenda_item_id"], name: "index_agenda_item_topics_on_agenda_item_id"
    t.index ["topic_id"], name: "index_agenda_item_topics_on_topic_id"
  end

  create_table "agenda_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "meeting_id", null: false
    t.string "number"
    t.integer "order_index"
    t.text "recommended_action"
    t.text "summary"
    t.text "title"
    t.datetime "updated_at", null: false
    t.index ["meeting_id"], name: "index_agenda_items_on_meeting_id"
  end

  create_table "entities", force: :cascade do |t|
    t.json "aliases"
    t.datetime "created_at", null: false
    t.string "entity_type"
    t.string "name"
    t.text "notes"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "entity_facts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.text "fact_text"
    t.boolean "sensitive"
    t.json "source_ref"
    t.string "source_type"
    t.string "status"
    t.datetime "updated_at", null: false
    t.text "verification_notes"
    t.date "verified_on"
    t.index ["entity_id"], name: "index_entity_facts_on_entity_id"
  end

  create_table "entity_mentions", force: :cascade do |t|
    t.string "context"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "meeting_document_id", null: false
    t.bigint "meeting_id", null: false
    t.integer "page_number"
    t.text "quote"
    t.string "raw_name"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_entity_mentions_on_entity_id"
    t.index ["meeting_document_id"], name: "index_entity_mentions_on_meeting_document_id"
    t.index ["meeting_id"], name: "index_entity_mentions_on_meeting_id"
  end

  create_table "extractions", force: :cascade do |t|
    t.text "cleaned_text"
    t.datetime "created_at", null: false
    t.bigint "meeting_document_id", null: false
    t.integer "page_number"
    t.text "raw_text"
    t.datetime "updated_at", null: false
    t.index ["meeting_document_id"], name: "index_extractions_on_meeting_document_id"
  end

  create_table "knowledge_chunks", force: :cascade do |t|
    t.integer "chunk_index"
    t.text "content"
    t.datetime "created_at", null: false
    t.json "embedding"
    t.bigint "knowledge_source_id", null: false
    t.json "metadata"
    t.datetime "updated_at", null: false
    t.index ["knowledge_source_id"], name: "index_knowledge_chunks_on_knowledge_source_id"
  end

  create_table "knowledge_source_topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "knowledge_source_id", null: false
    t.float "relevance_score", default: 0.0
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.index ["knowledge_source_id", "topic_id"], name: "index_ks_topics_on_source_and_topic", unique: true
    t.index ["knowledge_source_id"], name: "index_knowledge_source_topics_on_knowledge_source_id"
    t.index ["topic_id"], name: "index_knowledge_source_topics_on_topic_id"
  end

  create_table "knowledge_sources", force: :cascade do |t|
    t.boolean "active"
    t.text "body"
    t.datetime "created_at", null: false
    t.string "source_type"
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.text "verification_notes"
    t.date "verified_on"
  end

  create_table "meeting_documents", force: :cascade do |t|
    t.float "avg_chars_per_page"
    t.bigint "content_length"
    t.datetime "created_at", null: false
    t.string "document_type"
    t.string "etag"
    t.text "extracted_text"
    t.datetime "fetched_at"
    t.datetime "last_modified"
    t.bigint "meeting_id", null: false
    t.string "ocr_status"
    t.integer "page_count"
    t.tsvector "search_vector"
    t.string "sha256"
    t.string "source_url"
    t.integer "text_chars"
    t.string "text_quality"
    t.datetime "updated_at", null: false
    t.index ["meeting_id"], name: "index_meeting_documents_on_meeting_id"
    t.index ["search_vector"], name: "index_meeting_documents_on_search_vector", using: :gin
  end

  create_table "meeting_summaries", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "meeting_id", null: false
    t.string "summary_type"
    t.datetime "updated_at", null: false
    t.index ["meeting_id"], name: "index_meeting_summaries_on_meeting_id"
  end

  create_table "meetings", force: :cascade do |t|
    t.string "body_name"
    t.datetime "created_at", null: false
    t.string "detail_page_url"
    t.string "location"
    t.string "meeting_type"
    t.datetime "starts_at"
    t.string "status"
    t.datetime "updated_at", null: false
  end

  create_table "members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_members_on_name"
  end

  create_table "motions", force: :cascade do |t|
    t.bigint "agenda_item_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "meeting_id", null: false
    t.string "outcome"
    t.datetime "updated_at", null: false
    t.index ["agenda_item_id"], name: "index_motions_on_agenda_item_id"
    t.index ["meeting_id"], name: "index_motions_on_meeting_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stance_observations", force: :cascade do |t|
    t.float "confidence"
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.bigint "meeting_document_id", null: false
    t.bigint "meeting_id", null: false
    t.integer "page_number"
    t.string "position"
    t.text "quote"
    t.float "sentiment"
    t.string "topic"
    t.datetime "updated_at", null: false
    t.index ["entity_id"], name: "index_stance_observations_on_entity_id"
    t.index ["meeting_document_id"], name: "index_stance_observations_on_meeting_document_id"
    t.index ["meeting_id"], name: "index_stance_observations_on_meeting_id"
  end

  create_table "topic_aliases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_topic_aliases_on_name", unique: true
    t.index ["topic_id"], name: "index_topic_aliases_on_topic_id"
  end

  create_table "topic_appearances", force: :cascade do |t|
    t.bigint "agenda_item_id"
    t.datetime "appeared_at", null: false
    t.string "body_name"
    t.datetime "created_at", null: false
    t.string "evidence_type", null: false
    t.bigint "meeting_id", null: false
    t.jsonb "source_ref"
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["agenda_item_id"], name: "index_topic_appearances_on_agenda_item_id"
    t.index ["meeting_id"], name: "index_topic_appearances_on_meeting_id"
    t.index ["topic_id", "appeared_at"], name: "index_topic_appearances_on_topic_id_and_appeared_at"
    t.index ["topic_id"], name: "index_topic_appearances_on_topic_id"
  end

  create_table "topic_blocklists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_topic_blocklists_on_name", unique: true
  end

  create_table "topic_review_events", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.text "reason"
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["created_at"], name: "index_topic_review_events_on_created_at"
    t.index ["topic_id", "created_at"], name: "index_topic_review_events_on_topic_id_and_created_at"
    t.index ["topic_id"], name: "index_topic_review_events_on_topic_id"
    t.index ["user_id"], name: "index_topic_review_events_on_user_id"
  end

  create_table "topic_status_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "evidence_type", null: false
    t.string "lifecycle_status", null: false
    t.text "notes"
    t.datetime "occurred_at", null: false
    t.jsonb "source_ref"
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["topic_id", "occurred_at"], name: "index_topic_status_events_on_topic_id_and_occurred_at"
    t.index ["topic_id"], name: "index_topic_status_events_on_topic_id"
  end

  create_table "topic_summaries", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "generation_data", default: {}
    t.bigint "meeting_id", null: false
    t.string "summary_type", default: "topic_digest", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index ["meeting_id"], name: "index_topic_summaries_on_meeting_id"
    t.index ["topic_id", "meeting_id", "summary_type"], name: "idx_on_topic_id_meeting_id_summary_type_4aa4bd999d", unique: true
    t.index ["topic_id"], name: "index_topic_summaries_on_topic_id"
  end

  create_table "topics", force: :cascade do |t|
    t.string "canonical_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "first_seen_at"
    t.integer "importance", default: 0
    t.datetime "last_activity_at"
    t.datetime "last_seen_at"
    t.string "lifecycle_status"
    t.string "name"
    t.boolean "pinned", default: false, null: false
    t.datetime "resident_impact_overridden_at"
    t.integer "resident_impact_score"
    t.jsonb "resident_reported_context", default: {}, null: false
    t.string "review_status"
    t.string "slug"
    t.string "status", default: "approved", null: false
    t.datetime "updated_at", null: false
    t.index ["canonical_name"], name: "index_topics_on_canonical_name", unique: true
    t.index ["first_seen_at"], name: "index_topics_on_first_seen_at"
    t.index ["lifecycle_status"], name: "index_topics_on_lifecycle_status"
    t.index ["name"], name: "index_topics_on_name"
    t.index ["name"], name: "index_topics_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["resident_impact_score"], name: "index_topics_on_resident_impact_score"
    t.index ["review_status"], name: "index_topics_on_review_status"
    t.index ["slug"], name: "index_topics_on_slug", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.text "recovery_codes_digest", default: [], null: false, array: true
    t.boolean "totp_enabled", default: false, null: false
    t.string "totp_secret"
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "member_id", null: false
    t.bigint "motion_id", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.index ["member_id"], name: "index_votes_on_member_id"
    t.index ["motion_id"], name: "index_votes_on_motion_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agenda_item_documents", "agenda_items"
  add_foreign_key "agenda_item_documents", "meeting_documents"
  add_foreign_key "agenda_item_topics", "agenda_items"
  add_foreign_key "agenda_item_topics", "topics"
  add_foreign_key "agenda_items", "meetings"
  add_foreign_key "entity_facts", "entities"
  add_foreign_key "entity_mentions", "entities"
  add_foreign_key "entity_mentions", "meeting_documents"
  add_foreign_key "entity_mentions", "meetings"
  add_foreign_key "extractions", "meeting_documents"
  add_foreign_key "knowledge_chunks", "knowledge_sources"
  add_foreign_key "knowledge_source_topics", "knowledge_sources"
  add_foreign_key "knowledge_source_topics", "topics"
  add_foreign_key "meeting_documents", "meetings"
  add_foreign_key "meeting_summaries", "meetings"
  add_foreign_key "motions", "agenda_items"
  add_foreign_key "motions", "meetings"
  add_foreign_key "sessions", "users"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "stance_observations", "entities"
  add_foreign_key "stance_observations", "meeting_documents"
  add_foreign_key "stance_observations", "meetings"
  add_foreign_key "topic_aliases", "topics"
  add_foreign_key "topic_appearances", "agenda_items"
  add_foreign_key "topic_appearances", "meetings"
  add_foreign_key "topic_appearances", "topics"
  add_foreign_key "topic_review_events", "topics"
  add_foreign_key "topic_review_events", "users"
  add_foreign_key "topic_status_events", "topics"
  add_foreign_key "topic_summaries", "meetings"
  add_foreign_key "topic_summaries", "topics"
  add_foreign_key "votes", "members"
  add_foreign_key "votes", "motions"
end
