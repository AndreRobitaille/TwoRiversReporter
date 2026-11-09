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

ActiveRecord::Schema[8.1].define(version: 2026_11_09_004000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index [ "blob_id" ], name: "index_active_storage_attachments_on_blob_id"
    t.index [ "record_type", "record_id", "name", "blob_id" ], name: "index_active_storage_attachments_uniqueness", unique: true
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
    t.index [ "key" ], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index [ "blob_id", "variation_digest" ], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "agenda_item_documents", force: :cascade do |t|
    t.bigint "agenda_item_id", null: false
    t.datetime "created_at", null: false
    t.bigint "meeting_document_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "agenda_item_id" ], name: "index_agenda_item_documents_on_agenda_item_id"
    t.index [ "meeting_document_id" ], name: "index_agenda_item_documents_on_meeting_document_id"
  end

  create_table "agenda_item_topics", force: :cascade do |t|
    t.bigint "agenda_item_id", null: false
    t.datetime "created_at", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "agenda_item_id", "topic_id" ], name: "idx_agenda_item_topics_unique_pair", unique: true
    t.index [ "agenda_item_id" ], name: "index_agenda_item_topics_on_agenda_item_id"
    t.index [ "topic_id" ], name: "index_agenda_item_topics_on_topic_id"
  end

  create_table "agenda_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind"
    t.bigint "meeting_id", null: false
    t.string "number"
    t.integer "order_index"
    t.bigint "parent_id"
    t.text "recommended_action"
    t.text "summary"
    t.text "title"
    t.datetime "updated_at", null: false
    t.index [ "kind" ], name: "index_agenda_items_on_kind"
    t.index [ "meeting_id" ], name: "index_agenda_items_on_meeting_id"
    t.index [ "parent_id" ], name: "index_agenda_items_on_parent_id"
  end

  create_table "api_access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "display_hint", null: false
    t.datetime "expires_at", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.string "public_id", null: false
    t.datetime "revoked_at"
    t.string "secret_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index [ "expires_at" ], name: "index_api_access_tokens_on_expires_at"
    t.index [ "public_id" ], name: "index_api_access_tokens_on_public_id", unique: true
    t.index [ "user_id" ], name: "index_api_access_tokens_on_user_id"
  end

  create_table "audit_events", force: :cascade do |t|
    t.string "action", null: false
    t.string "actor_email"
    t.bigint "actor_id"
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.jsonb "metadata", default: {}, null: false
    t.bigint "subject_id"
    t.string "subject_label"
    t.string "subject_type"
    t.datetime "updated_at", null: false
    t.index [ "actor_id" ], name: "index_audit_events_on_actor_id"
    t.index [ "created_at" ], name: "index_audit_events_on_created_at"
    t.index [ "subject_type", "subject_id" ], name: "index_audit_events_on_subject_type_and_subject_id"
  end

  create_table "campaign_action_requests", force: :cascade do |t|
    t.bigint "campaign_action_review_id", null: false
    t.bigint "council_ai_reservation_id", null: false
    t.integer "attempt", null: false
    t.string "status", null: false
    t.jsonb "messages", null: false
    t.jsonb "request_parameters", null: false
    t.string "provider_response_id"
    t.string "response_model"
    t.string "finish_reason"
    t.jsonb "usage"
    t.text "response_body"
    t.string "error_class"
    t.integer "duration_ms"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "campaign_action_review_id", "attempt" ], name: "idx_on_campaign_action_review_id_attempt_374008eb13", unique: true
    t.index [ "campaign_action_review_id" ], name: "index_campaign_action_requests_on_campaign_action_review_id"
    t.index [ "council_ai_reservation_id" ], name: "index_campaign_action_requests_on_council_ai_reservation_id", unique: true
  end

  create_table "campaign_action_reviews", force: :cascade do |t|
    t.bigint "meeting_id"
    t.bigint "council_ai_budget_run_id"
    t.string "input_key", null: false
    t.jsonb "context", default: {}, null: false
    t.jsonb "parameters", default: {}, null: false
    t.jsonb "data", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.string "error_code"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_ai_budget_run_id" ], name: "index_campaign_action_reviews_on_council_ai_budget_run_id"
    t.index [ "input_key" ], name: "index_campaign_action_reviews_on_input_key", unique: true
    t.index [ "meeting_id" ], name: "index_campaign_action_reviews_on_meeting_id"
  end

  create_table "campaign_extractions", force: :cascade do |t|
    t.bigint "campaign_source_version_id", null: false
    t.bigint "council_ai_budget_run_id"
    t.bigint "reused_from_id"
    t.string "input_key", null: false
    t.jsonb "parameters", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.jsonb "data", default: {}, null: false
    t.string "error_code"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "purpose", default: "statements", null: false
    t.jsonb "context", default: {}, null: false
    t.index [ "campaign_source_version_id", "purpose" ], name: "idx_on_campaign_source_version_id_purpose_f796b010a7", unique: true
    t.index [ "council_ai_budget_run_id" ], name: "index_campaign_extractions_on_council_ai_budget_run_id"
    t.index [ "input_key" ], name: "index_campaign_extractions_on_input_key", unique: true
    t.index [ "reused_from_id" ], name: "index_campaign_extractions_on_reused_from_id"
  end

  create_table "campaign_requests", force: :cascade do |t|
    t.bigint "campaign_extraction_id", null: false
    t.bigint "council_ai_reservation_id", null: false
    t.integer "attempt", null: false
    t.string "status", null: false
    t.jsonb "messages", null: false
    t.jsonb "request_parameters", null: false
    t.string "provider_response_id"
    t.string "response_model"
    t.string "finish_reason"
    t.jsonb "usage"
    t.text "response_body"
    t.string "error_class"
    t.integer "duration_ms"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "campaign_extraction_id", "attempt" ], name: "index_campaign_requests_on_campaign_extraction_id_and_attempt", unique: true
    t.index [ "campaign_extraction_id" ], name: "index_campaign_requests_on_campaign_extraction_id"
    t.index [ "council_ai_reservation_id" ], name: "index_campaign_requests_on_council_ai_reservation_id", unique: true
  end

  create_table "campaign_source_versions", force: :cascade do |t|
    t.bigint "campaign_source_id", null: false
    t.string "title", null: false
    t.string "source_url", null: false
    t.string "publisher", null: false
    t.date "published_on"
    t.date "election_on", null: false
    t.string "coverage", default: "full_article", null: false
    t.text "coverage_notes"
    t.text "body", null: false
    t.string "version_key", null: false
    t.string "content_sha256", null: false
    t.bigint "submitted_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "prepared_transcript", default: {}, null: false
    t.index [ "campaign_source_id" ], name: "index_campaign_source_versions_on_campaign_source_id"
    t.index [ "submitted_by_id" ], name: "index_campaign_source_versions_on_submitted_by_id"
    t.index [ "version_key" ], name: "index_campaign_source_versions_on_version_key", unique: true
  end

  create_table "campaign_sources", force: :cascade do |t|
    t.string "title", null: false
    t.string "source_url", null: false
    t.string "publisher", null: false
    t.date "published_on"
    t.date "election_on", null: false
    t.string "coverage", default: "full_article", null: false
    t.text "coverage_notes"
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "prepared_transcript", default: {}, null: false
    t.index [ "source_url" ], name: "index_campaign_sources_on_source_url", unique: true
  end

  create_table "campaign_statement_topics", force: :cascade do |t|
    t.bigint "campaign_extraction_id", null: false
    t.bigint "campaign_statement_id", null: false
    t.bigint "topic_id", null: false
    t.bigint "original_topic_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "campaign_extraction_id", "campaign_statement_id", "original_topic_id" ], name: "idx_campaign_statement_topics_identity", unique: true
    t.index [ "campaign_extraction_id" ], name: "index_campaign_statement_topics_on_campaign_extraction_id"
    t.index [ "campaign_statement_id" ], name: "index_campaign_statement_topics_on_campaign_statement_id"
    t.index [ "topic_id" ], name: "index_campaign_statement_topics_on_topic_id"
  end

  create_table "campaign_statements", force: :cascade do |t|
    t.bigint "campaign_extraction_id", null: false
    t.bigint "member_id"
    t.integer "sequence", null: false
    t.string "status", null: false
    t.string "exception"
    t.string "validation_method", null: false
    t.datetime "validated_at", null: false
    t.jsonb "data", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "campaign_extraction_id", "sequence" ], name: "idx_on_campaign_extraction_id_sequence_3d52e6269b", unique: true
    t.index [ "campaign_extraction_id" ], name: "index_campaign_statements_on_campaign_extraction_id"
    t.index [ "member_id" ], name: "index_campaign_statements_on_member_id"
  end

  create_table "committee_aliases", force: :cascade do |t|
    t.bigint "committee_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index [ "committee_id" ], name: "index_committee_aliases_on_committee_id"
    t.index [ "name" ], name: "index_committee_aliases_on_name", unique: true
  end

  create_table "committee_memberships", force: :cascade do |t|
    t.bigint "committee_id", null: false
    t.datetime "created_at", null: false
    t.date "ended_on"
    t.bigint "member_id", null: false
    t.string "position_title"
    t.string "role"
    t.string "source", default: "admin_manual", null: false
    t.string "source_url"
    t.date "started_on"
    t.datetime "updated_at", null: false
    t.datetime "verified_at"
    t.index [ "committee_id", "member_id" ], name: "idx_committee_memberships_unique_active", unique: true, where: "(ended_on IS NULL)"
    t.index [ "committee_id" ], name: "index_committee_memberships_on_committee_id"
    t.index [ "member_id" ], name: "index_committee_memberships_on_member_id"
  end

  create_table "committees", force: :cascade do |t|
    t.string "committee_type", default: "city", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.date "dissolved_on"
    t.date "established_on"
    t.string "name", null: false
    t.string "slug", null: false
    t.string "status", default: "active", null: false
    t.datetime "updated_at", null: false
    t.index [ "name" ], name: "index_committees_on_name", unique: true
    t.index [ "slug" ], name: "index_committees_on_slug", unique: true
  end

  create_table "council_ai_budget_days", force: :cascade do |t|
    t.date "budget_on", null: false
    t.bigint "limit_microusd", null: false
    t.bigint "actor_id"
    t.bigint "original_actor_id", null: false
    t.datetime "authorized_at", null: false
    t.text "authorization_basis", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "actor_id" ], name: "index_council_ai_budget_days_on_actor_id"
    t.index [ "budget_on" ], name: "index_council_ai_budget_days_on_budget_on", unique: true
  end

  create_table "council_ai_budget_months", force: :cascade do |t|
    t.date "budget_month", null: false
    t.bigint "limit_microusd", null: false
    t.bigint "actor_id"
    t.bigint "original_actor_id", null: false
    t.datetime "authorized_at", null: false
    t.text "authorization_basis", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "live_actions", default: {}, null: false
    t.index [ "actor_id" ], name: "index_council_ai_budget_months_on_actor_id"
    t.index [ "budget_month" ], name: "index_council_ai_budget_months_on_budget_month", unique: true
  end

  create_table "council_ai_budget_runs", force: :cascade do |t|
    t.bigint "council_ai_budget_day_id", null: false
    t.bigint "limit_microusd", null: false
    t.bigint "request_limit_microusd", null: false
    t.integer "max_requests", null: false
    t.integer "max_concurrent", null: false
    t.integer "max_input_tokens", null: false
    t.integer "max_output_tokens", null: false
    t.datetime "expires_at", null: false
    t.bigint "actor_id"
    t.bigint "original_actor_id", null: false
    t.datetime "authorized_at", null: false
    t.text "authorization_basis", null: false
    t.jsonb "request_estimates", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "live_budget_month_id"
    t.index [ "actor_id" ], name: "index_council_ai_budget_runs_on_actor_id"
    t.index [ "council_ai_budget_day_id" ], name: "index_council_ai_budget_runs_on_council_ai_budget_day_id"
    t.index [ "live_budget_month_id" ], name: "index_council_ai_budget_runs_on_live_budget_month_id"
  end

  create_table "council_ai_reservations", force: :cascade do |t|
    t.bigint "council_ai_budget_run_id", null: false
    t.jsonb "request_estimate", null: false
    t.string "request_key", null: false
    t.bigint "reserved_microusd", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_ai_budget_run_id" ], name: "index_council_ai_reservations_on_council_ai_budget_run_id"
    t.index [ "request_key" ], name: "index_council_ai_reservations_on_request_key", unique: true
  end

  create_table "council_decision_assignments", force: :cascade do |t|
    t.bigint "observation_id", null: false
    t.bigint "minutes_extraction_id", null: false
    t.bigint "council_decision_id"
    t.bigint "correction_id"
    t.jsonb "conflicting_correction_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "correction_id" ], name: "index_council_decision_assignments_on_correction_id"
    t.index [ "council_decision_id" ], name: "index_council_decision_assignments_on_council_decision_id"
    t.index [ "minutes_extraction_id", "council_decision_id" ], name: "index_decision_assignments_on_stage_and_decision", unique: true
    t.index [ "minutes_extraction_id" ], name: "index_council_decision_assignments_on_minutes_extraction_id"
    t.index [ "observation_id" ], name: "index_council_decision_assignments_on_observation_id", unique: true
  end

  create_table "council_decision_corrections", force: :cascade do |t|
    t.bigint "observation_id", null: false
    t.bigint "basis_observation_id"
    t.bigint "before_decision_id"
    t.bigint "after_decision_id"
    t.bigint "previous_correction_id"
    t.bigint "actor_id"
    t.bigint "original_actor_id", null: false
    t.string "actor_email", null: false
    t.string "action", null: false
    t.text "reason", null: false
    t.string "request_id", null: false
    t.jsonb "request_manifest", null: false
    t.jsonb "evidence_manifest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "actor_id" ], name: "index_council_decision_corrections_on_actor_id"
    t.index [ "after_decision_id" ], name: "index_council_decision_corrections_on_after_decision_id"
    t.index [ "basis_observation_id" ], name: "index_council_decision_corrections_on_basis_observation_id"
    t.index [ "before_decision_id" ], name: "index_council_decision_corrections_on_before_decision_id"
    t.index [ "observation_id" ], name: "index_council_decision_corrections_on_observation_id"
    t.index [ "previous_correction_id" ], name: "index_council_decision_corrections_on_previous_correction_id"
    t.index [ "request_id" ], name: "index_council_decision_corrections_on_request_id", unique: true
  end

  create_table "council_decision_observations", force: :cascade do |t|
    t.bigint "minutes_extraction_id", null: false
    t.bigint "council_decision_id"
    t.integer "sequence", null: false
    t.jsonb "data", null: false
    t.jsonb "location_check", null: false
    t.jsonb "agenda_context", null: false
    t.string "identity_status", null: false
    t.string "reason"
    t.jsonb "candidate_decision_ids", default: [], null: false
    t.string "rule_version", null: false
    t.string "evidence_status", default: "extracted", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_decision_id" ], name: "index_council_decision_observations_on_council_decision_id"
    t.index [ "minutes_extraction_id", "council_decision_id" ], name: "index_decision_observations_on_stage_and_decision", unique: true
    t.index [ "minutes_extraction_id", "sequence" ], name: "index_decision_observations_on_stage_and_sequence", unique: true
    t.index [ "minutes_extraction_id" ], name: "index_council_decision_observations_on_minutes_extraction_id"
  end

  create_table "council_decisions", force: :cascade do |t|
    t.bigint "meeting_id"
    t.bigint "original_meeting_id", null: false
    t.string "public_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "meeting_id" ], name: "index_council_decisions_on_meeting_id"
    t.index [ "public_id" ], name: "index_council_decisions_on_public_id", unique: true
  end

  create_table "council_formal_requests", force: :cascade do |t|
    t.bigint "council_formal_review_id", null: false
    t.bigint "council_ai_reservation_id", null: false
    t.integer "attempt", null: false
    t.string "status", null: false
    t.jsonb "messages", null: false
    t.jsonb "request_parameters", null: false
    t.string "provider_response_id"
    t.string "response_model"
    t.string "finish_reason"
    t.jsonb "usage"
    t.text "response_body"
    t.string "error_class"
    t.integer "duration_ms"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_ai_reservation_id" ], name: "index_council_formal_requests_on_council_ai_reservation_id", unique: true
    t.index [ "council_formal_review_id", "attempt" ], name: "idx_on_council_formal_review_id_attempt_f8ed94027c", unique: true
    t.index [ "council_formal_review_id" ], name: "index_council_formal_requests_on_council_formal_review_id"
  end

  create_table "council_formal_reviews", force: :cascade do |t|
    t.bigint "council_formal_source_id", null: false
    t.bigint "council_ai_budget_run_id"
    t.string "input_key", null: false
    t.jsonb "context", default: {}, null: false
    t.jsonb "parameters", default: {}, null: false
    t.jsonb "data", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.string "error_code"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_ai_budget_run_id" ], name: "index_council_formal_reviews_on_council_ai_budget_run_id"
    t.index [ "council_formal_source_id" ], name: "index_council_formal_reviews_on_council_formal_source_id"
    t.index [ "input_key" ], name: "index_council_formal_reviews_on_input_key", unique: true
  end

  create_table "council_formal_sources", force: :cascade do |t|
    t.string "title", null: false
    t.string "case_reference", null: false
    t.string "reviewing_body", null: false
    t.string "policy_label"
    t.string "source_url", null: false
    t.string "record_kind", null: false
    t.date "published_on", null: false
    t.text "permitted_text", null: false
    t.jsonb "subject_names", default: [], null: false
    t.jsonb "service_period_keys", default: [], null: false
    t.text "private_notes"
    t.boolean "active", default: true, null: false
    t.bigint "verified_by_id"
    t.datetime "verified_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "source_url" ], name: "index_council_formal_sources_on_source_url", unique: true
    t.index [ "verified_by_id" ], name: "index_council_formal_sources_on_verified_by_id"
  end

  create_table "council_issue_requests", force: :cascade do |t|
    t.bigint "council_issue_review_id", null: false
    t.bigint "council_ai_reservation_id", null: false
    t.integer "attempt", null: false
    t.string "status", null: false
    t.jsonb "messages", null: false
    t.jsonb "request_parameters", null: false
    t.string "provider_response_id"
    t.string "response_model"
    t.string "finish_reason"
    t.jsonb "usage"
    t.text "response_body"
    t.string "error_class"
    t.integer "duration_ms"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_ai_reservation_id" ], name: "index_council_issue_requests_on_council_ai_reservation_id", unique: true
    t.index [ "council_issue_review_id", "attempt" ], name: "idx_on_council_issue_review_id_attempt_1de8765df9", unique: true
    t.index [ "council_issue_review_id" ], name: "index_council_issue_requests_on_council_issue_review_id"
  end

  create_table "council_issue_reviews", force: :cascade do |t|
    t.bigint "meeting_document_id"
    t.bigint "council_ai_budget_run_id"
    t.string "input_key", null: false
    t.jsonb "context", default: {}, null: false
    t.jsonb "parameters", default: {}, null: false
    t.jsonb "data", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.string "error_code"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "council_ai_budget_run_id" ], name: "index_council_issue_reviews_on_council_ai_budget_run_id"
    t.index [ "input_key" ], name: "index_council_issue_reviews_on_input_key", unique: true
    t.index [ "meeting_document_id" ], name: "index_council_issue_reviews_on_meeting_document_id"
  end

  create_table "council_service_periods", force: :cascade do |t|
    t.bigint "member_id", null: false
    t.string "period_key", null: false
    t.date "started_on", null: false
    t.date "ended_on"
    t.bigint "start_source_version_id", null: false
    t.integer "start_page", null: false
    t.bigint "end_source_version_id"
    t.integer "end_page"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "end_source_version_id" ], name: "index_council_service_periods_on_end_source_version_id"
    t.index [ "member_id", "period_key" ], name: "index_council_service_periods_on_member_id_and_period_key", unique: true
    t.index [ "member_id" ], name: "index_council_service_periods_on_member_id"
    t.index [ "start_source_version_id" ], name: "index_council_service_periods_on_start_source_version_id"
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
    t.index [ "entity_id" ], name: "index_entity_facts_on_entity_id"
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
    t.index [ "entity_id" ], name: "index_entity_mentions_on_entity_id"
    t.index [ "meeting_document_id" ], name: "index_entity_mentions_on_meeting_document_id"
    t.index [ "meeting_id" ], name: "index_entity_mentions_on_meeting_id"
  end

  create_table "extractions", force: :cascade do |t|
    t.text "cleaned_text"
    t.datetime "created_at", null: false
    t.bigint "meeting_document_id", null: false
    t.integer "page_number"
    t.text "raw_text"
    t.datetime "updated_at", null: false
    t.index [ "meeting_document_id" ], name: "index_extractions_on_meeting_document_id"
  end

  create_table "generated_images", force: :cascade do |t|
    t.boolean "admin_override", default: false, null: false
    t.datetime "created_at", null: false
    t.text "custom_prompt"
    t.text "failure_reason"
    t.datetime "generated_at"
    t.bigint "imageable_id", null: false
    t.string "imageable_type", null: false
    t.string "model"
    t.string "output_format"
    t.text "prompt"
    t.string "purpose", default: "feature_and_og", null: false
    t.string "requested_size"
    t.integer "retry_count", default: 0, null: false
    t.bigint "source_briefing_id"
    t.string "source_content_fingerprint"
    t.string "source_generation_tier"
    t.bigint "source_summary_id"
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.jsonb "visual_brief", default: {}, null: false
    t.index [ "imageable_type", "imageable_id", "status", "purpose" ], name: "index_generated_images_current_lookup"
    t.index [ "imageable_type", "imageable_id" ], name: "index_generated_images_on_imageable"
    t.index [ "source_briefing_id" ], name: "index_generated_images_on_source_briefing_id"
    t.index [ "source_content_fingerprint" ], name: "index_generated_images_on_source_content_fingerprint"
    t.index [ "source_summary_id" ], name: "index_generated_images_on_source_summary_id"
    t.index [ "uploaded_by_id" ], name: "index_generated_images_on_uploaded_by_id"
  end

  create_table "knowledge_chunks", force: :cascade do |t|
    t.integer "chunk_index"
    t.text "content"
    t.datetime "created_at", null: false
    t.json "embedding"
    t.bigint "knowledge_source_id", null: false
    t.json "metadata"
    t.datetime "updated_at", null: false
    t.index [ "knowledge_source_id" ], name: "index_knowledge_chunks_on_knowledge_source_id"
  end

  create_table "knowledge_source_topics", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "knowledge_source_id", null: false
    t.float "relevance_score", default: 0.0
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.boolean "verified", default: false
    t.index [ "knowledge_source_id", "topic_id" ], name: "index_ks_topics_on_source_and_topic", unique: true
    t.index [ "knowledge_source_id" ], name: "index_knowledge_source_topics_on_knowledge_source_id"
    t.index [ "topic_id" ], name: "index_knowledge_source_topics_on_topic_id"
  end

  create_table "knowledge_sources", force: :cascade do |t|
    t.boolean "active"
    t.text "body"
    t.float "confidence"
    t.datetime "created_at", null: false
    t.bigint "meeting_id"
    t.string "origin", default: "manual", null: false
    t.text "reasoning"
    t.string "source_type"
    t.date "stated_at"
    t.string "status", default: "approved"
    t.string "title"
    t.datetime "updated_at", null: false
    t.text "verification_notes"
    t.date "verified_on"
    t.bigint "source_summary_id"
    t.jsonb "source_summary_manifest"
    t.datetime "evidence_withdrawn_at"
    t.jsonb "source_catalog"
    t.index [ "meeting_id" ], name: "index_knowledge_sources_on_meeting_id"
    t.index [ "origin" ], name: "index_knowledge_sources_on_origin"
    t.index [ "source_catalog" ], name: "index_knowledge_sources_on_source_catalog", using: :gin
    t.index [ "source_summary_id" ], name: "index_knowledge_sources_on_source_summary_id"
    t.index [ "status" ], name: "index_knowledge_sources_on_status"
  end

  create_table "known_contexts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_fingerprint"
    t.string "ip_prefix"
    t.datetime "last_seen_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index [ "last_seen_at" ], name: "index_known_contexts_on_last_seen_at"
    t.index [ "user_id", "ip_prefix", "device_fingerprint" ], name: "index_known_contexts_on_user_and_context", unique: true, nulls_not_distinct: true
    t.index [ "user_id" ], name: "index_known_contexts_on_user_id"
  end

  create_table "magic_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "purpose", null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index [ "token_digest" ], name: "index_magic_links_on_token_digest", unique: true
    t.index [ "user_id", "purpose" ], name: "index_magic_links_on_user_id_and_purpose"
    t.index [ "user_id" ], name: "index_magic_links_on_user_id"
  end

  create_table "meeting_attendances", force: :cascade do |t|
    t.string "attendee_type", null: false
    t.string "capacity"
    t.datetime "created_at", null: false
    t.bigint "meeting_id", null: false
    t.bigint "member_id", null: false
    t.string "status", null: false
    t.datetime "updated_at", null: false
    t.jsonb "participation_notes", default: [], null: false
    t.index [ "meeting_id", "member_id" ], name: "index_meeting_attendances_on_meeting_id_and_member_id", unique: true
    t.index [ "meeting_id" ], name: "index_meeting_attendances_on_meeting_id"
    t.index [ "member_id" ], name: "index_meeting_attendances_on_member_id"
  end

  create_table "meeting_document_text_versions", force: :cascade do |t|
    t.bigint "meeting_document_version_id", null: false
    t.string "fingerprint", null: false
    t.string "extractor_version", null: false
    t.string "evidence_status", default: "extracted", null: false
    t.integer "page_count", null: false
    t.string "text_quality", null: false
    t.text "extracted_text", null: false
    t.jsonb "pages", default: [], null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "fingerprint" ], name: "index_meeting_document_text_versions_on_fingerprint", unique: true
    t.index [ "meeting_document_version_id" ], name: "idx_on_meeting_document_version_id_5edfcede8a"
  end

  create_table "meeting_document_versions", force: :cascade do |t|
    t.bigint "meeting_document_id"
    t.bigint "original_document_id", null: false
    t.string "version_key", null: false
    t.string "sha256", null: false
    t.text "source_url", null: false
    t.string "document_type", null: false
    t.bigint "original_meeting_id", null: false
    t.datetime "meeting_starts_at"
    t.datetime "retrieved_at", null: false
    t.datetime "source_last_modified"
    t.datetime "published_at"
    t.string "evidence_status", default: "collected", null: false
    t.string "capture_method", default: "download_sha256_v1", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "meeting_document_id" ], name: "index_meeting_document_versions_on_meeting_document_id"
    t.index [ "version_key" ], name: "index_meeting_document_versions_on_version_key", unique: true
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
    t.bigint "latest_text_version_id"
    t.index [ "latest_text_version_id" ], name: "index_meeting_documents_on_latest_text_version_id"
    t.index [ "meeting_id" ], name: "index_meeting_documents_on_meeting_id"
    t.index [ "search_vector" ], name: "index_meeting_documents_on_search_vector", using: :gin
  end

  create_table "meeting_summaries", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.jsonb "generation_data", default: {}
    t.bigint "meeting_id", null: false
    t.string "summary_type"
    t.datetime "updated_at", null: false
    t.datetime "evidence_withdrawn_at"
    t.index [ "meeting_id" ], name: "index_meeting_summaries_on_meeting_id"
  end

  create_table "meetings", force: :cascade do |t|
    t.string "agenda_structure_digest"
    t.string "body_name"
    t.bigint "committee_id"
    t.datetime "created_at", null: false
    t.string "detail_page_url"
    t.string "location"
    t.datetime "meeting_page_parsed_at"
    t.string "meeting_type"
    t.jsonb "processing_state", default: {}
    t.datetime "starts_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "minutes_publication_id"
    t.boolean "council_ai_budget_required", default: false, null: false
    t.bigint "council_ai_budget_run_id"
    t.index [ "committee_id" ], name: "index_meetings_on_committee_id"
    t.index [ "council_ai_budget_run_id" ], name: "index_meetings_on_council_ai_budget_run_id"
    t.index [ "minutes_publication_id" ], name: "index_meetings_on_minutes_publication_id"
  end

  create_table "member_aliases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "member_id", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index [ "member_id" ], name: "index_member_aliases_on_member_id"
    t.index [ "name" ], name: "index_member_aliases_on_name", unique: true
  end

  create_table "member_positions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "ended_on"
    t.string "kind", null: false
    t.bigint "member_id", null: false
    t.string "source", null: false
    t.string "source_url", null: false
    t.date "started_on"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.datetime "verified_at", null: false
    t.index [ "member_id", "kind" ], name: "idx_member_positions_unique_active", unique: true, where: "(ended_on IS NULL)"
    t.index [ "member_id" ], name: "index_member_positions_on_member_id"
  end

  create_table "members", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name"
    t.datetime "updated_at", null: false
    t.index [ "name" ], name: "index_members_on_name", unique: true
  end

  create_table "membership_applications", force: :cascade do |t|
    t.datetime "admin_notification_sent_at"
    t.text "application_notes"
    t.string "city"
    t.datetime "created_at", null: false
    t.text "decision_reason"
    t.string "facebook_profile_url"
    t.string "first_name"
    t.string "last_name"
    t.string "phone"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.string "state"
    t.string "status", default: "email_pending", null: false
    t.string "street"
    t.datetime "submitted_at"
    t.string "submitted_ip"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index [ "reviewed_by_id" ], name: "index_membership_applications_on_reviewed_by_id"
    t.index [ "status" ], name: "index_membership_applications_on_status"
    t.index [ "user_id" ], name: "index_membership_applications_on_user_id"
  end

  create_table "minutes_extractions", force: :cascade do |t|
    t.bigint "meeting_id"
    t.bigint "original_meeting_id", null: false
    t.bigint "meeting_document_text_version_id"
    t.string "kind", null: false
    t.string "input_key", null: false
    t.string "source_key", null: false
    t.jsonb "input_manifest", null: false
    t.text "source_text", null: false
    t.jsonb "data"
    t.string "status", default: "pending", null: false
    t.integer "attempts", default: 0, null: false
    t.string "error_code"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "evidence_locations"
    t.boolean "budget_required", default: false, null: false
    t.bigint "council_ai_budget_run_id"
    t.index [ "council_ai_budget_run_id" ], name: "index_minutes_extractions_on_council_ai_budget_run_id"
    t.index [ "input_key" ], name: "index_minutes_extractions_on_input_key", unique: true
    t.index [ "meeting_document_text_version_id" ], name: "index_minutes_extractions_on_meeting_document_text_version_id"
    t.index [ "meeting_id" ], name: "index_minutes_extractions_on_meeting_id"
    t.index [ "source_key", "kind", "status" ], name: "index_minutes_extractions_on_source_key_and_kind_and_status"
  end

  create_table "minutes_publications", force: :cascade do |t|
    t.bigint "meeting_id"
    t.bigint "original_meeting_id", null: false
    t.bigint "votes_extraction_id", null: false
    t.bigint "attendance_extraction_id", null: false
    t.string "fingerprint", null: false
    t.jsonb "projection_context", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index [ "attendance_extraction_id" ], name: "index_minutes_publications_on_attendance_extraction_id"
    t.index [ "fingerprint" ], name: "index_minutes_publications_on_fingerprint", unique: true
    t.index [ "meeting_id" ], name: "index_minutes_publications_on_meeting_id"
    t.index [ "votes_extraction_id" ], name: "index_minutes_publications_on_votes_extraction_id"
  end

  create_table "minutes_requests", force: :cascade do |t|
    t.bigint "minutes_extraction_id", null: false
    t.integer "attempt", null: false
    t.string "status", null: false
    t.jsonb "messages", null: false
    t.jsonb "request_parameters", null: false
    t.string "provider_response_id"
    t.string "response_model"
    t.string "finish_reason"
    t.jsonb "usage"
    t.text "response_body"
    t.string "error_class"
    t.integer "duration_ms"
    t.datetime "started_at", null: false
    t.datetime "finished_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "council_ai_reservation_id"
    t.index [ "council_ai_reservation_id" ], name: "index_minutes_requests_on_council_ai_reservation_id", unique: true
    t.index [ "minutes_extraction_id", "attempt" ], name: "index_minutes_requests_on_minutes_extraction_id_and_attempt", unique: true
    t.index [ "minutes_extraction_id" ], name: "index_minutes_requests_on_minutes_extraction_id"
    t.check_constraint "attempt > 0", name: "minutes_requests_positive_attempt"
  end

  create_table "motions", force: :cascade do |t|
    t.bigint "agenda_item_id"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "meeting_id", null: false
    t.string "outcome"
    t.datetime "updated_at", null: false
    t.bigint "decision_observation_id"
    t.index [ "agenda_item_id" ], name: "index_motions_on_agenda_item_id"
    t.index [ "decision_observation_id" ], name: "index_motions_on_decision_observation_id", unique: true
    t.index [ "meeting_id" ], name: "index_motions_on_meeting_id"
  end

  create_table "passkey_credentials", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "external_id", null: false
    t.datetime "last_used_at"
    t.string "nickname"
    t.text "public_key", null: false
    t.integer "sign_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index [ "external_id" ], name: "index_passkey_credentials_on_external_id", unique: true
    t.index [ "user_id" ], name: "index_passkey_credentials_on_user_id"
  end

  create_table "prompt_runs", force: :cascade do |t|
    t.string "ai_model", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.jsonb "messages", default: [], null: false
    t.jsonb "placeholder_values"
    t.string "prompt_template_key", null: false
    t.text "response_body", null: false
    t.string "response_format"
    t.bigint "source_id"
    t.string "source_type"
    t.float "temperature"
    t.index [ "prompt_template_key", "created_at" ], name: "index_prompt_runs_on_prompt_template_key_and_created_at"
    t.index [ "source_type", "source_id" ], name: "index_prompt_runs_on_source_type_and_source_id"
  end

  create_table "prompt_templates", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "description"
    t.text "instructions", null: false
    t.string "key", null: false
    t.string "model_tier", default: "default", null: false
    t.string "name", null: false
    t.jsonb "placeholders", default: [], null: false
    t.text "system_role"
    t.datetime "updated_at", null: false
    t.text "usage_context"
    t.index [ "key" ], name: "index_prompt_templates_on_key", unique: true
  end

  create_table "prompt_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "editor_note"
    t.text "instructions", null: false
    t.string "model_tier", null: false
    t.bigint "prompt_template_id", null: false
    t.text "system_role"
    t.index [ "prompt_template_id", "created_at" ], name: "index_prompt_versions_on_prompt_template_id_and_created_at"
    t.index [ "prompt_template_id" ], name: "index_prompt_versions_on_prompt_template_id"
  end

  create_table "redirects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "destination", null: false
    t.integer "hits", default: 0, null: false
    t.text "note"
    t.string "source_path", null: false
    t.integer "status_code", default: 301, null: false
    t.datetime "updated_at", null: false
    t.index [ "source_path" ], name: "index_redirects_on_source_path", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "device_fingerprint"
    t.string "ip_address"
    t.string "ip_prefix"
    t.datetime "last_seen_at"
    t.datetime "reauthenticated_at"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index [ "user_id" ], name: "index_sessions_on_user_id"
  end

  create_table "sign_in_attempts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "updated_at", null: false
    t.index [ "email_address", "created_at" ], name: "index_sign_in_attempts_on_email_address_and_created_at"
  end

  create_table "site_settings", force: :cascade do |t|
    t.string "access_mode", default: "open", null: false
    t.datetime "created_at", null: false
    t.integer "singleton_guard", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index [ "singleton_guard" ], name: "index_site_settings_on_singleton_guard", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index [ "concurrency_key", "priority", "job_id" ], name: "index_solid_queue_blocked_executions_for_release"
    t.index [ "expires_at", "concurrency_key" ], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index [ "job_id" ], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index [ "job_id" ], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index [ "process_id", "job_id" ], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index [ "job_id" ], name: "index_solid_queue_failed_executions_on_job_id", unique: true
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
    t.index [ "active_job_id" ], name: "index_solid_queue_jobs_on_active_job_id"
    t.index [ "class_name" ], name: "index_solid_queue_jobs_on_class_name"
    t.index [ "finished_at" ], name: "index_solid_queue_jobs_on_finished_at"
    t.index [ "queue_name", "finished_at" ], name: "index_solid_queue_jobs_for_filtering"
    t.index [ "scheduled_at", "finished_at" ], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index [ "queue_name" ], name: "index_solid_queue_pauses_on_queue_name", unique: true
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
    t.index [ "last_heartbeat_at" ], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index [ "name", "supervisor_id" ], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index [ "supervisor_id" ], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index [ "job_id" ], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index [ "priority", "job_id" ], name: "index_solid_queue_poll_all"
    t.index [ "queue_name", "priority", "job_id" ], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index [ "job_id" ], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index [ "task_key", "run_at" ], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
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
    t.index [ "key" ], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index [ "static" ], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index [ "job_id" ], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index [ "scheduled_at", "priority", "job_id" ], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index [ "expires_at" ], name: "index_solid_queue_semaphores_on_expires_at"
    t.index [ "key", "value" ], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index [ "key" ], name: "index_solid_queue_semaphores_on_key", unique: true
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
    t.index [ "entity_id" ], name: "index_stance_observations_on_entity_id"
    t.index [ "meeting_document_id" ], name: "index_stance_observations_on_meeting_document_id"
    t.index [ "meeting_id" ], name: "index_stance_observations_on_meeting_id"
  end

  create_table "topic_aliases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "name" ], name: "index_topic_aliases_on_name", unique: true
    t.index [ "topic_id" ], name: "index_topic_aliases_on_topic_id"
  end

  create_table "topic_appearances", force: :cascade do |t|
    t.bigint "agenda_item_id"
    t.datetime "appeared_at", null: false
    t.string "body_name"
    t.bigint "committee_id"
    t.datetime "created_at", null: false
    t.string "evidence_type", null: false
    t.bigint "meeting_id", null: false
    t.jsonb "source_ref"
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "agenda_item_id" ], name: "index_topic_appearances_on_agenda_item_id"
    t.index [ "committee_id" ], name: "index_topic_appearances_on_committee_id"
    t.index [ "meeting_id" ], name: "index_topic_appearances_on_meeting_id"
    t.index [ "topic_id", "appeared_at" ], name: "index_topic_appearances_on_topic_id_and_appeared_at"
    t.index [ "topic_id", "meeting_id", "agenda_item_id" ], name: "idx_topic_appearances_unique_triple", unique: true
    t.index [ "topic_id" ], name: "index_topic_appearances_on_topic_id"
  end

  create_table "topic_blocklists", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "reason"
    t.datetime "updated_at", null: false
    t.index [ "name" ], name: "index_topic_blocklists_on_name", unique: true
  end

  create_table "topic_briefings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "editorial_content"
    t.jsonb "generation_data", default: {}, null: false
    t.string "generation_tier", null: false
    t.string "headline", null: false
    t.datetime "last_full_generation_at"
    t.text "record_content"
    t.bigint "topic_id", null: false
    t.bigint "triggering_meeting_id"
    t.string "upcoming_headline"
    t.datetime "updated_at", null: false
    t.datetime "evidence_withdrawn_at"
    t.bigint "withdrawal_correction_id"
    t.index [ "topic_id" ], name: "index_topic_briefings_on_topic_id", unique: true
    t.index [ "triggering_meeting_id" ], name: "index_topic_briefings_on_triggering_meeting_id"
    t.index [ "withdrawal_correction_id" ], name: "index_topic_briefings_on_withdrawal_correction_id"
  end

  create_table "topic_review_events", force: :cascade do |t|
    t.string "action", null: false
    t.boolean "automated", default: false, null: false
    t.float "confidence"
    t.datetime "created_at", null: false
    t.text "reason"
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index [ "created_at" ], name: "index_topic_review_events_on_created_at"
    t.index [ "topic_id", "created_at" ], name: "index_topic_review_events_on_topic_id_and_created_at"
    t.index [ "topic_id" ], name: "index_topic_review_events_on_topic_id"
    t.index [ "user_id" ], name: "index_topic_review_events_on_user_id"
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
    t.bigint "decision_observation_id"
    t.index [ "decision_observation_id" ], name: "index_topic_status_events_on_decision_observation_id"
    t.index [ "topic_id", "decision_observation_id", "evidence_type" ], name: "index_topic_events_on_retained_decision"
    t.index [ "topic_id", "occurred_at" ], name: "index_topic_status_events_on_topic_id_and_occurred_at"
    t.index [ "topic_id" ], name: "index_topic_status_events_on_topic_id"
  end

  create_table "topic_summaries", force: :cascade do |t|
    t.text "content", null: false
    t.datetime "created_at", null: false
    t.jsonb "generation_data", default: {}
    t.bigint "meeting_id", null: false
    t.string "summary_type", default: "topic_digest", null: false
    t.bigint "topic_id", null: false
    t.datetime "updated_at", null: false
    t.index [ "meeting_id" ], name: "index_topic_summaries_on_meeting_id"
    t.index [ "topic_id", "meeting_id", "summary_type" ], name: "idx_on_topic_id_meeting_id_summary_type_4aa4bd999d", unique: true
    t.index [ "topic_id" ], name: "index_topic_summaries_on_topic_id"
  end

  create_table "topics", force: :cascade do |t|
    t.string "canonical_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "description_generated_at"
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
    t.string "reuse_strategy", default: "canonical", null: false
    t.string "review_status"
    t.string "slug"
    t.string "status", default: "approved", null: false
    t.datetime "updated_at", null: false
    t.index [ "canonical_name" ], name: "index_topics_on_canonical_name", unique: true
    t.index [ "first_seen_at" ], name: "index_topics_on_first_seen_at"
    t.index [ "lifecycle_status" ], name: "index_topics_on_lifecycle_status"
    t.index [ "name" ], name: "index_topics_on_name"
    t.index [ "name" ], name: "index_topics_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index [ "resident_impact_score" ], name: "index_topics_on_resident_impact_score"
    t.index [ "reuse_strategy" ], name: "index_topics_on_reuse_strategy"
    t.index [ "review_status" ], name: "index_topics_on_review_status"
    t.index [ "slug" ], name: "index_topics_on_slug", unique: true
  end

  create_table "transcript_imports", force: :cascade do |t|
    t.json "affected_topic_ids", default: [], null: false
    t.datetime "created_at", null: false
    t.text "error_backtrace"
    t.string "error_class"
    t.text "error_message"
    t.datetime "finished_at"
    t.bigint "meeting_document_id"
    t.bigint "meeting_id", null: false
    t.datetime "started_at"
    t.string "status", default: "queued", null: false
    t.json "step_logs", default: [], null: false
    t.datetime "updated_at", null: false
    t.string "youtube_url", null: false
    t.index [ "created_at" ], name: "index_transcript_imports_on_created_at"
    t.index [ "meeting_document_id" ], name: "index_transcript_imports_on_meeting_document_id"
    t.index [ "meeting_id" ], name: "index_transcript_imports_on_meeting_id"
    t.index [ "status" ], name: "index_transcript_imports_on_status"
  end

  create_table "users", force: :cascade do |t|
    t.boolean "admin", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "disabled_at"
    t.string "email_address", null: false
    t.datetime "email_verified_at"
    t.datetime "passkey_prompt_dismissed_until"
    t.string "status", default: "pending"
    t.datetime "updated_at", null: false
    t.string "webauthn_id"
    t.index [ "email_address" ], name: "index_users_on_email_address", unique: true
    t.index [ "status" ], name: "index_users_on_status"
    t.index [ "webauthn_id" ], name: "index_users_on_webauthn_id", unique: true
  end

  create_table "votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "member_id", null: false
    t.bigint "motion_id", null: false
    t.datetime "updated_at", null: false
    t.string "value"
    t.string "evidence_basis", default: "legacy", null: false
    t.index [ "member_id" ], name: "index_votes_on_member_id"
    t.index [ "motion_id", "member_id" ], name: "idx_votes_unique_per_motion", unique: true
    t.index [ "motion_id" ], name: "index_votes_on_motion_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "agenda_item_documents", "agenda_items"
  add_foreign_key "agenda_item_documents", "meeting_documents"
  add_foreign_key "agenda_item_topics", "agenda_items"
  add_foreign_key "agenda_item_topics", "topics"
  add_foreign_key "agenda_items", "agenda_items", column: "parent_id"
  add_foreign_key "agenda_items", "meetings"
  add_foreign_key "api_access_tokens", "users"
  add_foreign_key "audit_events", "users", column: "actor_id"
  add_foreign_key "campaign_action_requests", "campaign_action_reviews"
  add_foreign_key "campaign_action_requests", "council_ai_reservations"
  add_foreign_key "campaign_action_reviews", "council_ai_budget_runs"
  add_foreign_key "campaign_action_reviews", "meetings", on_delete: :nullify
  add_foreign_key "campaign_extractions", "campaign_extractions", column: "reused_from_id"
  add_foreign_key "campaign_extractions", "campaign_source_versions"
  add_foreign_key "campaign_extractions", "council_ai_budget_runs"
  add_foreign_key "campaign_requests", "campaign_extractions"
  add_foreign_key "campaign_requests", "council_ai_reservations"
  add_foreign_key "campaign_source_versions", "campaign_sources"
  add_foreign_key "campaign_source_versions", "users", column: "submitted_by_id", on_delete: :nullify
  add_foreign_key "campaign_statement_topics", "campaign_extractions"
  add_foreign_key "campaign_statement_topics", "campaign_statements"
  add_foreign_key "campaign_statement_topics", "topics"
  add_foreign_key "campaign_statements", "campaign_extractions"
  add_foreign_key "campaign_statements", "members", on_delete: :nullify
  add_foreign_key "committee_aliases", "committees"
  add_foreign_key "committee_memberships", "committees"
  add_foreign_key "committee_memberships", "members"
  add_foreign_key "council_ai_budget_days", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "council_ai_budget_months", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "council_ai_budget_runs", "council_ai_budget_days"
  add_foreign_key "council_ai_budget_runs", "council_ai_budget_months", column: "live_budget_month_id"
  add_foreign_key "council_ai_budget_runs", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "council_ai_reservations", "council_ai_budget_runs"
  add_foreign_key "council_decision_assignments", "council_decision_corrections", column: "correction_id"
  add_foreign_key "council_decision_assignments", "council_decision_observations", column: "observation_id"
  add_foreign_key "council_decision_assignments", "council_decisions"
  add_foreign_key "council_decision_assignments", "minutes_extractions"
  add_foreign_key "council_decision_corrections", "council_decision_corrections", column: "previous_correction_id"
  add_foreign_key "council_decision_corrections", "council_decision_observations", column: "basis_observation_id"
  add_foreign_key "council_decision_corrections", "council_decision_observations", column: "observation_id"
  add_foreign_key "council_decision_corrections", "council_decisions", column: "after_decision_id"
  add_foreign_key "council_decision_corrections", "council_decisions", column: "before_decision_id"
  add_foreign_key "council_decision_corrections", "users", column: "actor_id", on_delete: :nullify
  add_foreign_key "council_decision_observations", "council_decisions"
  add_foreign_key "council_decision_observations", "minutes_extractions"
  add_foreign_key "council_decisions", "meetings", on_delete: :nullify
  add_foreign_key "council_formal_requests", "council_ai_reservations"
  add_foreign_key "council_formal_requests", "council_formal_reviews"
  add_foreign_key "council_formal_reviews", "council_ai_budget_runs"
  add_foreign_key "council_formal_reviews", "council_formal_sources"
  add_foreign_key "council_formal_sources", "users", column: "verified_by_id", on_delete: :nullify
  add_foreign_key "council_issue_requests", "council_ai_reservations"
  add_foreign_key "council_issue_requests", "council_issue_reviews"
  add_foreign_key "council_issue_reviews", "council_ai_budget_runs"
  add_foreign_key "council_issue_reviews", "meeting_documents", on_delete: :nullify
  add_foreign_key "council_service_periods", "meeting_document_versions", column: "end_source_version_id"
  add_foreign_key "council_service_periods", "meeting_document_versions", column: "start_source_version_id"
  add_foreign_key "council_service_periods", "members"
  add_foreign_key "entity_facts", "entities"
  add_foreign_key "entity_mentions", "entities"
  add_foreign_key "entity_mentions", "meeting_documents"
  add_foreign_key "entity_mentions", "meetings"
  add_foreign_key "extractions", "meeting_documents"
  add_foreign_key "generated_images", "meeting_summaries", column: "source_summary_id", on_delete: :nullify
  add_foreign_key "generated_images", "topic_briefings", column: "source_briefing_id", on_delete: :nullify
  add_foreign_key "generated_images", "users", column: "uploaded_by_id"
  add_foreign_key "knowledge_chunks", "knowledge_sources"
  add_foreign_key "knowledge_source_topics", "knowledge_sources"
  add_foreign_key "knowledge_source_topics", "topics"
  add_foreign_key "knowledge_sources", "meeting_summaries", column: "source_summary_id", on_delete: :nullify
  add_foreign_key "knowledge_sources", "meetings"
  add_foreign_key "known_contexts", "users"
  add_foreign_key "magic_links", "users"
  add_foreign_key "meeting_attendances", "meetings"
  add_foreign_key "meeting_attendances", "members"
  add_foreign_key "meeting_document_text_versions", "meeting_document_versions"
  add_foreign_key "meeting_document_versions", "meeting_documents", on_delete: :nullify
  add_foreign_key "meeting_documents", "meeting_document_text_versions", column: "latest_text_version_id"
  add_foreign_key "meeting_documents", "meetings"
  add_foreign_key "meeting_summaries", "meetings"
  add_foreign_key "meetings", "committees"
  add_foreign_key "meetings", "council_ai_budget_runs"
  add_foreign_key "meetings", "minutes_publications"
  add_foreign_key "member_aliases", "members"
  add_foreign_key "member_positions", "members"
  add_foreign_key "membership_applications", "users"
  add_foreign_key "membership_applications", "users", column: "reviewed_by_id"
  add_foreign_key "minutes_extractions", "council_ai_budget_runs"
  add_foreign_key "minutes_extractions", "meeting_document_text_versions"
  add_foreign_key "minutes_extractions", "meetings", on_delete: :nullify
  add_foreign_key "minutes_publications", "meetings", on_delete: :nullify
  add_foreign_key "minutes_publications", "minutes_extractions", column: "attendance_extraction_id"
  add_foreign_key "minutes_publications", "minutes_extractions", column: "votes_extraction_id"
  add_foreign_key "minutes_requests", "council_ai_reservations"
  add_foreign_key "minutes_requests", "minutes_extractions"
  add_foreign_key "motions", "agenda_items"
  add_foreign_key "motions", "council_decision_observations", column: "decision_observation_id"
  add_foreign_key "motions", "meetings"
  add_foreign_key "passkey_credentials", "users"
  add_foreign_key "prompt_versions", "prompt_templates"
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
  add_foreign_key "topic_appearances", "committees"
  add_foreign_key "topic_appearances", "meetings"
  add_foreign_key "topic_appearances", "topics"
  add_foreign_key "topic_briefings", "council_decision_corrections", column: "withdrawal_correction_id"
  add_foreign_key "topic_briefings", "meetings", column: "triggering_meeting_id"
  add_foreign_key "topic_briefings", "topics"
  add_foreign_key "topic_review_events", "topics"
  add_foreign_key "topic_review_events", "users"
  add_foreign_key "topic_status_events", "council_decision_observations", column: "decision_observation_id"
  add_foreign_key "topic_status_events", "topics"
  add_foreign_key "topic_summaries", "meetings"
  add_foreign_key "topic_summaries", "topics"
  add_foreign_key "transcript_imports", "meeting_documents"
  add_foreign_key "transcript_imports", "meetings"
  add_foreign_key "votes", "members"
  add_foreign_key "votes", "motions"
end
