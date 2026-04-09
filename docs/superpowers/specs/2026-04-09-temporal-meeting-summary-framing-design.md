# Temporal Context for Meeting Summaries

**Date:** 2026-04-09
**Status:** Approved
**Scope:** `analyze_meeting_content` prompt and `SummarizeMeetingJob`

## Problem

Meeting summaries generated from agenda/packet documents use past tense and fabricate outcomes ("Council approved...", "residents pushed back on...") even when the meeting hasn't happened yet. The AI has no information about whether the meeting is in the future or past — no meeting date, no current date, no temporal framing instructions.

This isn't just a verb tense issue. The entire narrative posture is wrong: the AI invents debate, decisions, and public input that never occurred.

## Solution

Add a `<temporal_context>` block to the `analyze_meeting_content` prompt template with three framing modes derived from meeting date and document type. Same JSON output schema for all modes — the content and posture change, not the structure.

## Framing Matrix

| `meeting.starts_at > Date.current` | Document type | `framing` | Narrative posture |
|---|---|---|---|
| yes | packet | `preview` | Forward-looking: what's proposed, what's at stake, what to watch |
| no | packet | `stale_preview` | Agenda was available but no official results yet |
| no | minutes | `recap` | What happened (current default behavior) |
| no | transcript | `recap` | What happened, sourced from auto-captions |
| no | minutes + transcript | `recap` | Authoritative recap with supplementary detail |

## Changes

### 1. `Ai::OpenAiService#analyze_meeting_content`

Derive three new placeholder values from the `source` (Meeting) object:

```ruby
meeting_date = source.respond_to?(:starts_at) ? source.starts_at&.to_date : nil
today = Date.current

framing = if meeting_date && meeting_date > today
            "preview"
          elsif type.to_s == "minutes" || type.to_s == "transcript"
            "recap"
          else
            "stale_preview"
          end
```

Add to `placeholders` hash:
- `meeting_date:` — the meeting's date as a string (e.g. "2026-04-15")
- `today:` — current date as a string (e.g. "2026-04-09")
- `temporal_framing:` — "preview", "recap", or "stale_preview"

The `framing` value is also computed by `SummarizeMeetingJob` (same inputs: meeting date and document type) and passed to `save_summary` for storage in `generation_data`. The service method does not need to return it.

### 2. Prompt template: `analyze_meeting_content`

Add a `<temporal_context>` block after `<document_scope>`, before `<guidelines>`:

```
<temporal_context>
Today's date: {{today}}. This meeting is scheduled for {{meeting_date}}.

{{temporal_framing}} is one of: preview, recap, stale_preview.

If "preview": This meeting HAS NOT OCCURRED. You are writing a preview
based on the agenda/packet. Do not infer outcomes, reactions, decisions,
debate, or public input — none of that has happened yet. Frame everything
as what is proposed, what is at stake, and what residents should watch for.
Use future tense ("will consider", "is expected to", "is proposed").
headline should be forward-looking. highlights become "what to watch"
items. item_details describe what is being proposed and why it matters,
not what happened. decision and vote fields must be null.

If "recap": This meeting has occurred. Summarize what happened.

If "stale_preview": This meeting's date has passed, but only agenda/packet
text is available — no minutes or transcript. Do not fabricate outcomes.
Frame as: here is what was on the agenda. Note that official results are
not yet available. Use past tense for the scheduling ("was scheduled")
but do not state or imply any decisions, votes, or discussion occurred.
headline should note that results are pending. decision and vote fields
must be null.
</temporal_context>
```

Update the headline guideline — change from hardcoded "backward-looking" to:

```
- Headline: 1-2 sentences, max ~40 words. Follow the temporal_context
  framing for tense and posture.
```

### 3. `SummarizeMeetingJob`

**Store framing in `generation_data`:** The `save_summary` method gains a `framing:` keyword argument, stored as `generation_data["framing"]` alongside the existing `source_type`.

The job computes `framing` from `meeting.starts_at` and the document type (same logic as the service method) and passes it to `save_summary`.

**Clean up stale previews:** When a `minutes_recap` or `transcript_recap` is created, destroy any existing `packet_analysis` summary for the same meeting:

```ruby
meeting.meeting_summaries.where(summary_type: "packet_analysis").destroy_all
```

Added to both the minutes branch and the transcript branch, following the existing pattern for `transcript_recap` cleanup (line 47).

### 4. No changes to `save_summary` priority cascade

The existing priority logic (minutes > transcript > packet) is unchanged. Framing derivation happens inside `analyze_meeting_content` based on meeting date and document type.

## Explicitly Out of Scope

- **No view changes** — no banners, no conditional section headers, no rendering differences. The content communicates its own framing.
- **No topic summary changes** — `analyze_topic_summary` stays as-is. Topic summaries are citation-grounded and longitudinal; temporal fabrication hasn't been observed. Revisit if concrete examples surface.
- **No schema changes** — same JSON output structure for all framings. `decision`/`vote` naturally null in previews.
- **No migration** — `framing` stored in existing `generation_data` JSON column.

## Transition Behavior

When a meeting goes from preview → recap (minutes or transcript arrive):

1. Minutes/transcript branch runs as normal, creates `minutes_recap` or `transcript_recap`
2. Old `packet_analysis` is destroyed (new cleanup line)
3. Old `transcript_recap` is destroyed when `minutes_recap` arrives (existing behavior)
4. The `framing` field in `generation_data` naturally reflects the new state

No re-summarization trigger needed — the existing pipeline already re-summarizes when new documents arrive.
