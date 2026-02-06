# Issue 24: Update meeting list status badges

## Summary
Replace the document-count bubble on the main meeting list with a single, time-linear status badge that reflects document availability.

## Background
The meeting list currently displays a bubble with the number of attached documents. The desired behavior is to show a single status badge that communicates whether a meeting has no info yet, has an agenda, or has minutes.

## Requirements
- Remove the existing document-count bubble from the meeting list UI.
- Add a single status badge for each meeting, mutually exclusive and time-linear:
  - "No info yet" when there is no meaningful info (usually no PDFs).
  - "Has Agenda" when an agenda PDF exists but no packet or minutes PDF exists.
  - "Has Packet" when a packet PDF exists but no minutes PDF exists.
  - "Has Minutes" when a minutes PDF exists.

## Open questions
- What is the exact page name/route for the main meeting list in this app?
- What data conditions define agenda vs minutes PDFs (e.g., document types, filename patterns, tags)?

## Implementation Details
- **Meeting List Page**: `app/views/meetings/index.html.erb`
- **Meeting Model**: `app/models/meeting.rb` - added `document_status` method.
- **Criteria**:
  - `Has Minutes`: `minutes_pdf` exists.
  - `Has Packet`: `packet_pdf` exists, and no `minutes_pdf`.
  - `Has Agenda`: `agenda_pdf` exists, and no `packet_pdf` or `minutes_pdf`.
  - `No info yet`: No relevant PDFs found.

## Acceptance criteria
- [x] The document-count bubble is removed from the meeting list UI.
- [x] Exactly one of the four statuses is shown per meeting based on agreed criteria.
- [x] Statuses follow the intended progression: No info yet -> Has Agenda -> Has Packet -> Has Minutes.
