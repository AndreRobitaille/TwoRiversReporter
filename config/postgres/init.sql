-- Create additional databases for Solid Cache, Solid Queue, and Solid Cable.
-- The primary database is created automatically by POSTGRES_DB env var.
CREATE DATABASE two_rivers_reporter_production_cache;
CREATE DATABASE two_rivers_reporter_production_queue;
CREATE DATABASE two_rivers_reporter_production_cable;

-- Enable pgvector extension on the primary database.
\c two_rivers_reporter_production
CREATE EXTENSION IF NOT EXISTS vector;
