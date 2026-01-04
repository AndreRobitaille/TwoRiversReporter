# Two Rivers Meetings Transparency Site

This project builds a public-facing website for residents of Two Rivers, WI to:

- See **upcoming city meetings** as early as possible
- Understand **what is actually being discussed or decided**
- Review **past meetings**, including summaries, minutes, and voting behavior
- Hold elected officials and boards accountable using official records

The system ingests **official city-published documents** (PDFs and HTML),
preserves them as the source of truth, and produces **clearly labeled,
citation-backed summaries** for residents.

## Status
Early development.

## Design & Architecture
The authoritative software design and development plan lives here:

👉 `docs/DEVELOPMENT_PLAN.md`

That document defines:
- scope and non-goals
- data model
- ingestion pipeline
- summarization rules
- architectural constraints

Contributors and AI coding tools should treat it as binding.

## Tech Stack (planned)
- Ruby on Rails
- PostgreSQL
- Server-rendered HTML
- Background jobs for ingestion and analysis

## Non-Goals
- No SPA
- No microservices
- No commenting system
- No user accounts (initially)

## License
TBD
