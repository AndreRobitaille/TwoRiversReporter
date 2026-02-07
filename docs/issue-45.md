## Issue 45: Topic admin UX + aliasing fixes

### Summary
Improve the admin Topics list and detail page so admins can adjust importance inline, alias/merge topics quickly, sort columns, and view last activity. This is a follow-up to issue #37 to address broader topic quality and admin workflow improvements.

### Scope (from issue)
- Admin Topics list: inline edit Importance with explicit save button.
- Admin Topics list: merge/alias topics from the list using a search/selector popup.
- Admin Topics list: sortable columns by header click (toggle ascending/descending).
- Admin Topics list: add "Last acted on" column.
- Admin Topics list: integrate status into actions column (visual indicator + toggle button).
- Topic detail page: alias/merge flow should be fixed and consistent with the list view.
- Topic detail page: visual feedback when saving changes.

### Implementation Details

#### Admin Topics Index
1. **Columns Added:**
   - Importance (inline editable with number field 0-10)
   - Last Acted On (shows `last_activity_at` date)
   - Mentions count

2. **Sorting:**
   - Click column headers to sort
   - Toggle ascending/descending on each click
   - Columns: Name, Importance, Mentions, Last Seen, Last Acted On
   - Preserves filters and pagination

3. **Inline Importance Edit:**
   - Number input field with min/max 0-10 validation
   - Explicit "Save" button next to field
   - Button shows "Saving..." → "Saved!" (green) → "Save" feedback
   - Validation prevents values outside 0-10 range

4. **Status Integration:**
   - Removed separate Status column
   - Single button shows current state:
     - Red "Blocked" button → click to unblock
     - Green "Approved" button → click to block

5. **Alias/Merge Modal:**
   - "Alias/Merge" button opens modal
   - Search for target topic
   - Merge creates alias and moves all agenda items
   - Modal includes cancel and confirm buttons

#### Topic Detail Page
1. **Form Improvements:**
   - Fixed: Changed `summary` field to `description` (matches database schema)
   - Added min/max 0-10 validation on importance field
   - Visual feedback on save: button shows "Saving..." → "Saved!" → "Update Topic"

2. **Alias/Merge:**
   - Replaced long select dropdown with modal search UI
   - Consistent with list view modal

#### Technical Changes

**New Files:**
- `app/helpers/admin_helper.rb` - Sort link helpers with icon support
- `app/javascript/controllers/modal_controller.js` - Modal open/close logic
- `app/javascript/controllers/modal_trigger_controller.js` - Modal trigger handling
- `app/javascript/controllers/topic_search_controller.js` - Topic search in modal
- `app/javascript/controllers/inline_save_controller.js` - Inline form save feedback
- `app/javascript/controllers/form_feedback_controller.js` - Detail page form feedback
- `app/views/admin/topics/_merge_modal.html.erb` - Shared merge modal partial

**Modified Files:**
- `app/controllers/admin/topics_controller.rb` - Added sorting, search endpoint, JSON responses
- `app/views/admin/topics/index.html.erb` - New columns, sorting headers
- `app/views/admin/topics/_topic.html.erb` - Inline importance, status button, actions
- `app/views/admin/topics/show.html.erb` - Fixed fields, added save feedback, modal integration
- `app/models/topic.rb` - Added importance validation (0-10)
- `config/routes.rb` - Added search endpoint
- `app/assets/stylesheets/application.css` - Sort icon styles, utility classes

**Removed Files:**
- `app/views/admin/topics/_aliases_and_merge.html.erb` - Replaced by modal

### Validation & Constraints
- Importance must be integer between 0-10 (inclusive)
- Topic name is normalized (lowercase, no punctuation, trimmed)
- Alias names are unique across all topics
- Cannot merge a topic into itself

### Tests
- Integration tests for sorting, searching, inline updates, aliasing, and merging
- All existing tests pass

### Notes
- Removed "Pinned" badge from topic names (redundant with Pin/Unpin button)
- Status column removed in favor of integrated status/action button
- All form submissions now have clear visual feedback
