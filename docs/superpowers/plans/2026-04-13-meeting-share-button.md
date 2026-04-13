# Meeting Share Button Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a share button to the meeting detail page that lets residents share on Facebook or copy a formatted summary to clipboard.

**Architecture:** Server-side helper assembles share text from existing `generation_data`. Stimulus controller handles dropdown toggle, clipboard copy, and Facebook popup. OG meta tags added to the meeting `<head>` for link previews.

**Tech Stack:** Rails helpers, Stimulus.js, CSS, Facebook Share Dialog (no SDK/API key needed)

---

### Task 1: Share Text Helper — Past Meetings

**Files:**
- Modify: `app/helpers/meetings_helper.rb`
- Modify: `test/helpers/meetings_helper_test.rb`

- [ ] **Step 1: Write failing tests for `share_text` with past meeting + generation_data**

Add these tests to `test/helpers/meetings_helper_test.rb`, below the existing `decision_badge_class` tests:

```ruby
# --- share_text helper ---

test "share_text for past meeting with generation_data includes headline and highlights" do
  meeting = OpenStruct.new(
    id: 42,
    body_name: "Common Council Meeting",
    starts_at: 2.days.ago
  )
  summary = OpenStruct.new(generation_data: @generation_data)

  text = share_text(meeting, summary)

  assert_includes text, "Common Council"
  assert_no_match(/Common Council Meeting/, text) # strips " Meeting" suffix
  assert_includes text, meeting.starts_at.strftime("%B %-d, %Y")
  assert_includes text, meeting.starts_at.strftime("%-l:%M %p")
  assert_includes text, @generation_data["headline"]
  assert_includes text, "Key decisions:"
  assert_includes text, "Adopted intent-to-reimburse resolution"
  assert_includes text, "Tabled property assessment ordinance"
  assert_includes text, "https://tworiversmatters.com/meetings/42"
  assert_includes text, "Two Rivers Matters"
end

test "share_text for past meeting caps at 5 highlights" do
  many_highlights = 7.times.map { |i| { "text" => "Decision #{i}" } }
  gd = { "headline" => "Big meeting.", "highlights" => many_highlights }
  meeting = OpenStruct.new(id: 1, body_name: "Council Meeting", starts_at: 1.day.ago)
  summary = OpenStruct.new(generation_data: gd)

  text = share_text(meeting, summary)

  assert_equal 5, text.scan(/^ - /).size
end

test "share_text for past meeting includes vote when present" do
  meeting = OpenStruct.new(id: 1, body_name: "Council Meeting", starts_at: 1.day.ago)
  summary = OpenStruct.new(generation_data: @generation_data)

  text = share_text(meeting, summary)

  assert_includes text, "6-3"
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/meetings_helper_test.rb -n "/share_text/"` 
Expected: FAIL — `NoMethodError: undefined method 'share_text'`

- [ ] **Step 3: Implement `share_text` in MeetingsHelper**

Add to `app/helpers/meetings_helper.rb`, above the `private` section (there isn't one yet, so add at the end of the module):

```ruby
PRODUCTION_HOST = "tworiversmatters.com".freeze

def share_text(meeting, summary)
  lines = []

  # Header: body name (strip " Meeting" suffix) + date/time
  name = meeting.body_name.sub(/ Meeting$/, "")
  date = meeting.starts_at&.strftime("%B %-d, %Y")
  time = meeting.starts_at&.strftime("%-l:%M %p")
  lines << "#{name} — #{date}, #{time}"
  lines << ""

  gd = summary&.generation_data
  meeting_url = "https://#{PRODUCTION_HOST}/meetings/#{meeting.id}"

  if gd.present?
    # Headline paragraph
    headline = gd["headline"]
    lines << headline if headline.present?
    lines << "" if headline.present?

    upcoming = meeting.starts_at.present? && meeting.starts_at > Time.current

    if upcoming
      share_text_upcoming_bullets(lines, gd)
    else
      share_text_past_bullets(lines, gd)
    end
  elsif meeting.respond_to?(:agenda_items) && meeting.agenda_items.any?
    share_text_agenda_fallback(lines, meeting)
  end

  lines << "Full details at Two Rivers Matters:"
  lines << meeting_url

  lines.join("\n")
end

private

def share_text_past_bullets(lines, gd)
  highlights = gd["highlights"] || []
  return if highlights.empty?

  lines << "Key decisions:"
  highlights.first(5).each do |h|
    bullet = " - #{h["text"]}"
    bullet += " (#{h["vote"]})" if h["vote"].present?
    lines << bullet
  end
  lines << ""
end

def share_text_upcoming_bullets(lines, gd)
  items = gd["item_details"] || []
  return if items.empty?

  highlights = gd["highlights"] || []
  highlight_texts = highlights.map { |h| h["text"] }

  lines << "On the agenda:"
  items.first(5).each do |item|
    title = item["agenda_item_title"]
    # Find matching highlight for context
    match = highlights.detect { |h| h["text"]&.downcase&.include?(title&.downcase&.first(20).to_s) }
    if match
      lines << " - #{match["text"]}"
    else
      lines << " - #{title}"
    end
  end
  lines << ""
end

def share_text_agenda_fallback(lines, meeting)
  items = meeting.agenda_items
    .reject { |ai| ai.title&.match?(/\A(CALL TO ORDER|ROLL CALL|ADJOURNMENT|PUBLIC INPUT)\z/i) }
  return if items.empty?

  lines << "On the agenda:"
  items.first(5).each do |ai|
    lines << " - #{ai.title}"
  end
  lines << ""
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/meetings_helper_test.rb -n "/share_text/"`
Expected: 3 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/helpers/meetings_helper.rb test/helpers/meetings_helper_test.rb
git commit -m "feat: add share_text helper for past meetings with generation_data"
```

---

### Task 2: Share Text Helper — Upcoming Meetings & Fallbacks

**Files:**
- Modify: `app/helpers/meetings_helper.rb`
- Modify: `test/helpers/meetings_helper_test.rb`

- [ ] **Step 1: Write failing tests for upcoming and fallback cases**

Add to `test/helpers/meetings_helper_test.rb`:

```ruby
test "share_text for upcoming meeting uses 'On the agenda' and item_details" do
  meeting = OpenStruct.new(
    id: 154,
    body_name: "Plan Commission Meeting",
    starts_at: 2.days.from_now
  )
  summary = OpenStruct.new(generation_data: @generation_data)

  text = share_text(meeting, summary)

  assert_includes text, "Plan Commission"
  assert_includes text, "On the agenda:"
  assert_includes text, "Rezoning at 3204 Lincoln Ave"
end

test "share_text falls back to agenda items when no summary" do
  agenda_item = OpenStruct.new(title: "Budget Amendment Discussion")
  meeting = OpenStruct.new(
    id: 10,
    body_name: "Finance Committee Meeting",
    starts_at: 1.day.from_now,
    agenda_items: [agenda_item]
  )

  text = share_text(meeting, nil)

  assert_includes text, "Finance Committee"
  assert_includes text, "On the agenda:"
  assert_includes text, "Budget Amendment Discussion"
  assert_includes text, "https://tworiversmatters.com/meetings/10"
end

test "share_text agenda fallback filters procedural items" do
  items = [
    OpenStruct.new(title: "CALL TO ORDER"),
    OpenStruct.new(title: "ROLL CALL"),
    OpenStruct.new(title: "Water Rate Increase"),
    OpenStruct.new(title: "ADJOURNMENT")
  ]
  meeting = OpenStruct.new(
    id: 10,
    body_name: "Council Meeting",
    starts_at: 1.day.from_now,
    agenda_items: items
  )

  text = share_text(meeting, nil)

  assert_includes text, "Water Rate Increase"
  assert_no_match(/CALL TO ORDER/, text)
  assert_no_match(/ROLL CALL/, text)
  assert_no_match(/ADJOURNMENT/, text)
end

test "share_text minimal fallback when no summary and no agenda items" do
  meeting = OpenStruct.new(
    id: 10,
    body_name: "Council Meeting",
    starts_at: 1.day.from_now
  )

  text = share_text(meeting, nil)

  assert_includes text, "Council"
  assert_includes text, "https://tworiversmatters.com/meetings/10"
  assert_no_match(/On the agenda/, text)
  assert_no_match(/Key decisions/, text)
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/meetings_helper_test.rb -n "/share_text/"`
Expected: new tests FAIL (the upcoming test may pass if implementation from Task 1 is correct; the fallback tests will fail because `OpenStruct` doesn't have `agenda_items` responding to `.any?` correctly without setup — adjust if needed)

- [ ] **Step 3: Fix any failing tests**

The implementation from Task 1 should already handle upcoming + fallback cases. If the `agenda_items` fallback doesn't work with `OpenStruct` (no `.any?` on array), the test uses plain arrays which do respond to `.any?`, so it should work. Run and fix as needed.

- [ ] **Step 4: Run full helper test suite**

Run: `bin/rails test test/helpers/meetings_helper_test.rb`
Expected: all tests pass (existing + new)

- [ ] **Step 5: Commit**

```bash
git add test/helpers/meetings_helper_test.rb
git commit -m "test: add share_text tests for upcoming meetings and fallback tiers"
```

---

### Task 3: OG Meta Tags Helper

**Files:**
- Modify: `app/helpers/meetings_helper.rb`
- Modify: `test/helpers/meetings_helper_test.rb`

- [ ] **Step 1: Write failing tests for `share_og_description`**

Add to `test/helpers/meetings_helper_test.rb`:

```ruby
# --- OG meta helpers ---

test "share_og_description extracts headline truncated to 200 chars" do
  long_headline = "A" * 250
  summary = OpenStruct.new(generation_data: { "headline" => long_headline })

  result = share_og_description(summary)

  assert_equal 200, result.length
  assert result.end_with?("...")
end

test "share_og_description returns headline when under 200 chars" do
  summary = OpenStruct.new(generation_data: @generation_data)

  result = share_og_description(summary)

  assert_equal @generation_data["headline"], result
end

test "share_og_description returns default when no summary" do
  result = share_og_description(nil)

  assert_equal "Meeting details and AI-generated summary.", result
end

test "share_og_description returns default when no generation_data" do
  summary = OpenStruct.new(generation_data: nil)

  result = share_og_description(summary)

  assert_equal "Meeting details and AI-generated summary.", result
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/helpers/meetings_helper_test.rb -n "/share_og/"`
Expected: FAIL — `NoMethodError: undefined method 'share_og_description'`

- [ ] **Step 3: Implement `share_og_description`**

Add to `app/helpers/meetings_helper.rb` (in the public section, before `private`):

```ruby
def share_og_description(summary)
  headline = summary&.generation_data&.dig("headline")
  return "Meeting details and AI-generated summary." if headline.blank?
  return headline if headline.length <= 200

  headline[0..196] + "..."
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/helpers/meetings_helper_test.rb -n "/share_og/"`
Expected: 4 tests, 0 failures

- [ ] **Step 5: Commit**

```bash
git add app/helpers/meetings_helper.rb test/helpers/meetings_helper_test.rb
git commit -m "feat: add share_og_description helper for Open Graph meta tags"
```

---

### Task 4: Stimulus Share Controller

**Files:**
- Create: `app/javascript/controllers/share_controller.js`

- [ ] **Step 1: Create the Stimulus controller**

Create `app/javascript/controllers/share_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dropdown", "copyButton"]
  static values = { text: String, url: String }

  toggle(event) {
    event.stopPropagation()
    this.dropdownTarget.hidden = !this.dropdownTarget.hidden
  }

  facebook(event) {
    event.preventDefault()
    const shareUrl = `https://www.facebook.com/sharer/sharer.php?u=${encodeURIComponent(this.urlValue)}`
    const width = 600
    const height = 400
    const left = (screen.width - width) / 2
    const top = (screen.height - height) / 2
    window.open(shareUrl, "facebook-share", `width=${width},height=${height},left=${left},top=${top}`)
    this.dropdownTarget.hidden = true
  }

  copy(event) {
    event.preventDefault()
    navigator.clipboard.writeText(this.textValue).then(() => {
      const button = this.copyButtonTarget
      const original = button.textContent
      button.textContent = "Copied!"
      setTimeout(() => { button.textContent = original }, 2000)
    })
    this.dropdownTarget.hidden = true
  }

  close(event) {
    if (!this.element.contains(event.target)) {
      this.dropdownTarget.hidden = true
    }
  }

  closeOnEscape(event) {
    if (event.key === "Escape") {
      this.dropdownTarget.hidden = true
    }
  }
}
```

- [ ] **Step 2: Verify the controller is auto-registered**

Stimulus eager-loads from `controllers/` via `app/javascript/controllers/index.js`. No manual registration needed — the file name `share_controller.js` auto-registers as `share`.

Run: `bin/rails test` (smoke test — no JS test framework, but ensure no Ruby regressions)
Expected: all tests pass

- [ ] **Step 3: Commit**

```bash
git add app/javascript/controllers/share_controller.js
git commit -m "feat: add Stimulus share controller for dropdown, clipboard, Facebook"
```

---

### Task 5: CSS Styles for Share Button & Dropdown

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add share button and dropdown CSS**

Add after the `.meeting-doc-link svg` block (after line ~1731 in `application.css`):

```css
/* Share button — terra-cotta accent to differentiate from source links */
.meeting-doc-link--share {
  color: var(--color-terra-cotta);
  border-color: var(--color-terra-cotta);
}

.meeting-doc-link--share:hover {
  background: color-mix(in srgb, var(--color-terra-cotta) 10%, transparent);
  border-color: var(--color-terra-cotta);
  color: var(--color-terra-cotta);
}

.meeting-docs-separator {
  display: inline-block;
  width: 1px;
  height: 1rem;
  background: var(--color-border);
  align-self: center;
}

/* Share dropdown */
.share-wrapper {
  position: relative;
  display: inline-flex;
}

.share-dropdown {
  position: absolute;
  top: calc(100% + 0.3rem);
  right: 0;
  min-width: 10rem;
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-sm);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.08);
  z-index: 10;
  padding: 0.25rem 0;
}

.share-dropdown-item {
  display: block;
  width: 100%;
  padding: 0.4rem 0.75rem;
  font-family: var(--font-body);
  font-size: var(--font-size-sm);
  color: var(--color-text-secondary);
  text-decoration: none;
  text-align: left;
  background: none;
  border: none;
  cursor: pointer;
  transition: background var(--transition-fast);
}

.share-dropdown-item:hover {
  background: var(--color-surface-raised);
  color: var(--color-text);
}
```

- [ ] **Step 2: Verify styles load**

Run: `bin/dev` (if not already running) and inspect the meeting page in browser.
Expected: no CSS errors in console

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: add CSS for share button, separator, and dropdown"
```

---

### Task 6: Meeting Show View — OG Tags + Share Button Markup

**Files:**
- Modify: `app/views/meetings/show.html.erb`

- [ ] **Step 1: Add OG meta tags at the top of the template**

Add immediately after the existing `content_for(:title)` block (after line 1):

```erb
<% content_for(:head) do %>
  <meta property="og:title" content="<%= @meeting.body_name %> — <%= @meeting.starts_at&.strftime("%B %-d, %Y") %>">
  <meta property="og:description" content="<%= share_og_description(@summary) %>">
  <meta property="og:url" content="https://<%= MeetingsHelper::PRODUCTION_HOST %>/meetings/<%= @meeting.id %>">
  <meta property="og:type" content="article">
  <meta property="og:site_name" content="Two Rivers Matters">
<% end %>
```

- [ ] **Step 2: Add share button markup after the City Website link**

Replace the closing `</div>` of `.meeting-article-docs` (line 33) with the separator + share button + dropdown, then close the div:

After the City Website link (after line 32), add:

```erb
      <span class="meeting-docs-separator"></span>
      <div class="share-wrapper" data-controller="share"
           data-share-text-value="<%= share_text(@meeting, @summary) %>"
           data-share-url-value="https://<%= MeetingsHelper::PRODUCTION_HOST %>/meetings/<%= @meeting.id %>"
           data-action="click@window->share#close keydown.esc@window->share#closeOnEscape">
        <button type="button" class="meeting-doc-link meeting-doc-link--share" data-action="share#toggle">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M4 12v8a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2v-8"/><polyline points="16 6 12 2 8 6"/><line x1="12" y1="2" x2="12" y2="15"/></svg>
          Share
        </button>
        <div class="share-dropdown" data-share-target="dropdown" hidden>
          <button type="button" class="share-dropdown-item" data-action="share#facebook">Share on Facebook</button>
          <button type="button" class="share-dropdown-item" data-action="share#copy" data-share-target="copyButton">Copy summary</button>
        </div>
      </div>
```

- [ ] **Step 3: Test in browser — past meeting**

Open a past meeting with a summary (e.g., `/meetings/1` or another with `generation_data`).

Verify:
- Share button appears with terra-cotta accent after the separator
- Clicking opens dropdown with two options
- "Share on Facebook" opens a popup
- "Copy summary" copies text to clipboard (paste into a text editor to check)
- Dropdown closes on outside click and Escape key

- [ ] **Step 4: Test in browser — upcoming meeting**

Open `/meetings/154` (Plan Commission, upcoming).

Verify:
- Share button present
- Copy summary produces text with "On the agenda:" section
- Agenda items listed (not procedural items like CALL TO ORDER)

- [ ] **Step 5: Test in browser — meeting with no summary**

Find or note a meeting with no summary. Verify the share text falls back to just name + date + link (or agenda items if present).

- [ ] **Step 6: Commit**

```bash
git add app/views/meetings/show.html.erb
git commit -m "feat: add share button and OG meta tags to meeting show page"
```

---

### Task 7: Final Verification & Lint

**Files:** None (verification only)

- [ ] **Step 1: Run full test suite**

Run: `bin/rails test`
Expected: all tests pass

- [ ] **Step 2: Run linter**

Run: `bin/rubocop`
Expected: no new offenses (fix any that appear in changed files)

- [ ] **Step 3: Run CI**

Run: `bin/ci`
Expected: all checks pass

- [ ] **Step 4: Browser smoke test**

Test the full flow one more time:
1. Open a past meeting with a summary
2. Click Share → Copy summary → paste into a text editor — verify formatting
3. Click Share → Share on Facebook → verify popup opens with correct URL
4. Open an upcoming meeting → repeat
5. Check the page source for OG meta tags in `<head>`

- [ ] **Step 5: Commit any lint fixes**

```bash
git add -A
git commit -m "chore: lint fixes for meeting share feature"
```
