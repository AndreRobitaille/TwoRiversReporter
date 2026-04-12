# About Page Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static About page that answers "what is this site, who made it, and can I trust it?" for skeptical Two Rivers residents arriving from Facebook.

**Architecture:** New `PagesController` with a single `about` action, pure static ERB template (no database queries). Reuses `.topic-article` reading column and `.home-section-header` patterns. New `about.css` for page-specific styles (anchor bar, pipeline steps, Under the Hood zone). Heavy use of existing Atomic-era SVG motifs.

**Tech Stack:** Rails ERB views, plain CSS with custom properties, existing SVG partials.

**Design spec:** `docs/superpowers/specs/2026-04-12-about-page-design.md`

---

### Task 1: Route, Controller, and Smoke Test

**Files:**
- Create: `app/controllers/pages_controller.rb`
- Create: `app/views/pages/about.html.erb` (placeholder)
- Create: `test/controllers/pages_controller_test.rb`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write the failing test**

```ruby
# test/controllers/pages_controller_test.rb
require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "about page renders successfully" do
    get about_path
    assert_response :success
  end

  test "about page has correct title" do
    get about_path
    assert_select "title", /About/
  end

  test "about page contains anchor links" do
    get about_path
    assert_select "a[href='#how-it-works']"
    assert_select "a[href='#your-questions']"
    assert_select "a[href='#the-bias']"
    assert_select "a[href='#under-the-hood']"
  end

  test "about page contains all four zones" do
    get about_path
    assert_select "#how-it-works"
    assert_select "#your-questions"
    assert_select "#the-bias"
    assert_select "#under-the-hood"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: FAIL — `about_path` undefined (no route yet)

- [ ] **Step 3: Add route**

In `config/routes.rb`, add `get "about", to: "pages#about"` between the `root` line and the resources block:

```ruby
# config/routes.rb — after line 1 (root "home#index")
get "about", to: "pages#about"
```

- [ ] **Step 4: Create controller**

```ruby
# app/controllers/pages_controller.rb
class PagesController < ApplicationController
  def about
  end
end
```

- [ ] **Step 5: Create placeholder view**

```erb
<%# app/views/pages/about.html.erb %>
<% content_for(:title) { "About - Two Rivers Matters" } %>
<% content_for(:description) { "What this site is, where the information comes from, and why it exists. Built by a Two Rivers resident using the city's own public documents." } %>

<article class="topic-article about-page">

  <header class="about-hook">
    <span class="about-eyebrow">About This Site</span>
    <h1 class="topic-article-title">Not a City Website. Not the News.</h1>
    <p class="topic-article-dek">A Two Rivers resident built this to help you follow what's happening at city hall — using nothing but the city's own public documents.</p>
  </header>

  <nav class="about-anchor-bar">
    <a href="#how-it-works">How It Works</a>
    <a href="#your-questions">Your Questions</a>
    <a href="#the-bias">The Bias</a>
    <a href="#under-the-hood">Under the Hood</a>
  </nav>

  <section id="how-it-works"></section>
  <section id="your-questions"></section>
  <section id="the-bias"></section>
  <section id="under-the-hood"></section>

</article>
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: all 4 tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/controllers/pages_controller.rb app/views/pages/about.html.erb test/controllers/pages_controller_test.rb config/routes.rb
git commit -m "feat: add About page route, controller, and placeholder view"
```

---

### Task 2: Navigation and Sitemap

**Files:**
- Modify: `app/views/layouts/application.html.erb` (header nav + footer)
- Modify: `app/views/sitemaps/show.xml.erb`
- Modify: `test/controllers/sitemaps_controller_test.rb`

- [ ] **Step 1: Write the failing sitemap test**

Add to `test/controllers/sitemaps_controller_test.rb`:

```ruby
test "includes the about page" do
  get sitemap_path
  assert_includes @response.body, about_url
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/controllers/sitemaps_controller_test.rb -n "/about/"` 
Expected: FAIL — `about_url` not in sitemap

- [ ] **Step 3: Add About link to header nav**

In `app/views/layouts/application.html.erb`, after line 66 (`City Officials` link), add:

```erb
<%= link_to "About", about_path, class: ("active" if controller_name == "pages") %>
```

- [ ] **Step 4: Add About link to footer**

In `app/views/layouts/application.html.erb`, in the `footer-links` div (after the "City Website" link, line 88), add:

```erb
<%= link_to "About", about_path %>
```

- [ ] **Step 5: Add About to sitemap**

In `app/views/sitemaps/show.xml.erb`, after the root `<url>` block (after line 7), add:

```erb
<url>
  <loc><%= about_url %></loc>
  <changefreq>monthly</changefreq>
  <priority>0.6</priority>
</url>
```

- [ ] **Step 6: Run sitemap test**

Run: `bin/rails test test/controllers/sitemaps_controller_test.rb`
Expected: all tests PASS

- [ ] **Step 7: Commit**

```bash
git add app/views/layouts/application.html.erb app/views/sitemaps/show.xml.erb test/controllers/sitemaps_controller_test.rb
git commit -m "feat: add About link to nav, footer, and sitemap"
```

---

### Task 3: About Page CSS

**Files:**
- Create: `app/assets/stylesheets/about.css`

This task creates all the page-specific styles. The page reuses `.topic-article`, `.topic-article-title`, `.topic-article-dek`, `.home-section-header`, and existing SVG partials. New classes are scoped under `.about-page`.

- [ ] **Step 1: Create about.css**

```css
/* app/assets/stylesheets/about.css */

/* ============================================
   About Page
   ============================================ */

/* ---- Hook (Zone 1) ---- */

.about-hook {
  text-align: center;
  padding: var(--space-10) 0 var(--space-6);
  position: relative;
  overflow: hidden;
}

.about-hook .topic-article-title {
  text-align: center;
}

.about-hook .topic-article-dek {
  text-align: center;
  max-width: 32rem;
  margin-left: auto;
  margin-right: auto;
}

.about-eyebrow {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  letter-spacing: 0.15em;
  color: var(--color-terra-cotta);
  display: block;
  margin-bottom: var(--space-3);
}

.about-starburst-watermark {
  position: absolute;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%);
  pointer-events: none;
  z-index: 0;
}

.about-hook > * {
  position: relative;
  z-index: 1;
}

/* ---- Anchor Bar ---- */

.about-anchor-bar {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-4);
  flex-wrap: wrap;
  padding: var(--space-4) 0;
  margin-bottom: var(--space-8);
  border-top: 1.5px solid var(--color-border);
  border-bottom: 1.5px solid var(--color-border);
}

.about-anchor-bar a {
  font-family: var(--font-data);
  font-size: var(--font-size-xs);
  text-transform: uppercase;
  letter-spacing: 0.12em;
  color: var(--color-teal);
  text-decoration: none;
  padding-bottom: 2px;
  border-bottom: 2px solid transparent;
  transition: border-color var(--transition-fast);
}

.about-anchor-bar a:hover {
  border-bottom-color: var(--color-terra-cotta);
}

/* Atom marker separators between anchor links (hidden on wrap) */
.about-anchor-sep {
  color: var(--color-terra-cotta);
  display: flex;
  align-items: center;
}

@media (max-width: 480px) {
  .about-anchor-sep {
    display: none;
  }
  .about-anchor-bar {
    gap: var(--space-3);
  }
}

/* ---- Pipeline Steps (Zone 2) ---- */

.about-pipeline {
  list-style: none;
  padding: 0;
  margin: 0;
  display: flex;
  flex-direction: column;
  gap: var(--space-4);
}

.about-pipeline-step {
  background: var(--color-surface);
  padding: var(--space-4) var(--space-5);
  border-left: 3px solid var(--color-teal);
  border-radius: var(--radius-sm);
  box-shadow: var(--shadow-sm);
}

.about-pipeline-step strong {
  color: var(--color-teal);
}

.about-pipeline-step a {
  color: var(--color-teal);
  text-decoration: underline;
  text-decoration-color: var(--color-terra-cotta);
  text-underline-offset: 2px;
}

.about-pipeline-step a:hover {
  color: var(--color-primary-hover);
}

.about-pipeline-connector {
  text-align: center;
  color: var(--color-text-muted);
  font-size: var(--font-size-lg);
  line-height: 1;
  padding: 0;
  margin: calc(-1 * var(--space-2)) 0;
}

/* ---- FAQ (Zone 3) ---- */

.about-faq {
  list-style: none;
  padding: 0;
  margin: 0;
}

.about-faq-item {
  padding: var(--space-5) 0;
  border-bottom: 1px solid var(--color-border);
}

.about-faq-item:last-child {
  border-bottom: none;
}

.about-faq-question {
  font-family: var(--font-body);
  font-weight: 700;
  font-size: var(--font-size-lg);
  color: var(--color-text);
  margin: 0 0 var(--space-2);
}

.about-faq-answer {
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  line-height: var(--line-height-relaxed);
  color: var(--color-text-secondary);
  margin: 0;
}

.about-faq-answer + .about-faq-answer {
  margin-top: var(--space-3);
}

/* ---- Under the Hood (Zone 4) ---- */

.about-hood-zone {
  background: var(--color-primary-light);
  margin-left: calc(-1 * var(--space-5));
  margin-right: calc(-1 * var(--space-5));
  padding: var(--space-8) var(--space-5);
  border-radius: var(--radius-md);
}

.about-hood-section {
  margin-top: var(--space-8);
}

.about-hood-section:first-child {
  margin-top: 0;
}

.about-hood-heading {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--font-size-sm);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  color: var(--color-terra-cotta);
  margin: 0 0 var(--space-3);
}

.about-hood-zone p {
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  line-height: var(--line-height-relaxed);
  color: var(--color-text-secondary);
  margin: 0 0 var(--space-3);
}

.about-hood-zone p:last-child {
  margin-bottom: 0;
}

.about-hood-zone ul {
  padding-left: var(--space-5);
  margin: var(--space-2) 0 var(--space-3);
}

.about-hood-zone li {
  font-family: var(--font-body);
  font-size: var(--font-size-base);
  line-height: var(--line-height-relaxed);
  color: var(--color-text-secondary);
  margin-bottom: var(--space-2);
}

.about-hood-zone a {
  color: var(--color-teal);
  text-decoration: underline;
  text-decoration-color: var(--color-terra-cotta);
  text-underline-offset: 2px;
}

.about-hood-zone a:hover {
  color: var(--color-primary-hover);
}

/* Boomerang decorations */
.about-boomerang-left,
.about-boomerang-right {
  position: absolute;
  pointer-events: none;
  z-index: 0;
}

.about-boomerang-left {
  left: -60px;
  top: var(--space-8);
}

.about-boomerang-right {
  right: -60px;
  bottom: var(--space-8);
  transform: scaleX(-1);
}

/* Hide overflow decorations on narrow screens */
@media (max-width: 768px) {
  .about-boomerang-left,
  .about-boomerang-right {
    display: none;
  }
}
```

- [ ] **Step 2: Verify Propshaft picks it up**

Run: `bin/rails runner "puts Rails.application.assets.load_path.find('about.css')"`
Expected: prints the path to the file (Propshaft auto-discovers CSS in `app/assets/stylesheets/`)

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/about.css
git commit -m "feat: add About page styles (anchor bar, pipeline, FAQ, hood zone)"
```

---

### Task 4: Zone 1 — The Hook (Header + Starburst + Anchor Bar)

**Files:**
- Modify: `app/views/pages/about.html.erb`

Replace the placeholder content from Task 1 with the full hook and anchor bar, including the starburst watermark SVG.

- [ ] **Step 1: Write the full hook and anchor bar**

```erb
<%# app/views/pages/about.html.erb %>
<% content_for(:title) { "About - Two Rivers Matters" } %>
<% content_for(:description) { "What this site is, where the information comes from, and why it exists. Built by a Two Rivers resident using the city's own public documents." } %>

<article class="topic-article about-page">

  <%# === Zone 1: The Hook === %>
  <header class="about-hook">
    <div class="about-starburst-watermark">
      <%= render "shared/starburst", size: 240, opacity: 0.06 %>
    </div>
    <span class="about-eyebrow">About This Site</span>
    <h1 class="topic-article-title">Not a City Website.<br>Not the News.</h1>
    <p class="topic-article-dek">A Two Rivers resident built this to help you follow what's happening at city hall — using nothing but the city's own public documents.</p>
  </header>

  <%# === Anchor Bar === %>
  <nav class="about-anchor-bar" aria-label="Page sections">
    <a href="#how-it-works">How It Works</a>
    <span class="about-anchor-sep"><%= render "shared/atom_marker", size: 14 %></span>
    <a href="#your-questions">Your Questions</a>
    <span class="about-anchor-sep"><%= render "shared/atom_marker", size: 14 %></span>
    <a href="#the-bias">The Bias</a>
    <span class="about-anchor-sep"><%= render "shared/atom_marker", size: 14 %></span>
    <a href="#under-the-hood">Under the Hood</a>
  </nav>

  <%# Zones 2-4 will be added in subsequent tasks %>
  <section id="how-it-works"></section>
  <section id="your-questions"></section>
  <section id="the-bias"></section>
  <section id="under-the-hood"></section>

</article>
```

- [ ] **Step 2: Run existing tests**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: all 4 tests PASS

- [ ] **Step 3: Visually verify in browser**

Run: `bin/dev` (if not running), visit `/about`. Confirm:
- Starburst watermark visible behind title at low opacity
- "ABOUT THIS SITE" eyebrow in terra cotta DM Mono uppercase
- Title large, centered, Outfit uppercase, teal
- Subtitle centered below
- Anchor bar with atom marker separators, DM Mono uppercase links
- Terra cotta underline on hover

- [ ] **Step 4: Commit**

```bash
git add app/views/pages/about.html.erb
git commit -m "feat: About page Zone 1 — hook header with starburst and anchor bar"
```

---

### Task 5: Zone 2 — How It Works (Pipeline Steps)

**Files:**
- Modify: `app/views/pages/about.html.erb`

- [ ] **Step 1: Replace the `#how-it-works` placeholder**

Replace `<section id="how-it-works"></section>` with:

```erb
  <%# === Zone 2: How It Works === %>
  <section id="how-it-works" class="topic-article-section">
    <div class="home-section-header">
      <%= render "shared/atom_marker" %>
      <span class="section-label">How It Works</span>
      <span class="section-line"></span>
    </div>

    <ol class="about-pipeline">
      <li class="about-pipeline-step">
        <strong>The city posts meeting documents.</strong>
        Agendas, meeting packets, and official minutes. Wisconsin's Open Meetings Law
        (<a href="https://docs.legis.wisconsin.gov/statutes/statutes/19/v/84" target="_blank" rel="noopener">Wis.&nbsp;Stats.&nbsp;&sect;19.84</a>)
        requires them to be public. That's the only source this site uses — nothing private, nothing leaked.
      </li>
      <li class="about-pipeline-connector" aria-hidden="true">&darr;</li>
      <li class="about-pipeline-step">
        <strong>This site checks every night for new documents.</strong>
        New meeting dates, new agendas, new minutes. Copies are saved here so nothing
        disappears if the city reorganizes its website or removes old files.
      </li>
      <li class="about-pipeline-connector" aria-hidden="true">&darr;</li>
      <li class="about-pipeline-step">
        <strong>AI reads the documents and writes plain-language summaries.</strong>
        Not government-speak. Every claim links back to the original document so
        you can read it yourself and decide if you agree with how it was summarized.
      </li>
      <li class="about-pipeline-connector" aria-hidden="true">&darr;</li>
      <li class="about-pipeline-step">
        <strong>Issues are tracked across meetings, not just listed by date.</strong>
        Instead of making you dig through a dozen agendas, the site follows things
        like "downtown parking" or "lead pipe replacement" across months of meetings
        and connects them together automatically.
      </li>
    </ol>
  </section>
```

- [ ] **Step 2: Run tests**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: all 4 tests PASS

- [ ] **Step 3: Visually verify in browser**

Visit `/about`. Confirm:
- Section header with atom marker, "HOW IT WORKS" label, gradient line
- Four pipeline steps with teal left border
- Down-arrow connectors between steps
- Wisconsin statute link works (opens in new tab)

- [ ] **Step 4: Commit**

```bash
git add app/views/pages/about.html.erb
git commit -m "feat: About page Zone 2 — How It Works pipeline steps"
```

---

### Task 6: Zone 3 — Your Questions + The Bias (FAQ)

**Files:**
- Modify: `app/views/pages/about.html.erb`

- [ ] **Step 1: Replace both the `#your-questions` and `#the-bias` placeholders**

Replace `<section id="your-questions"></section>` and `<section id="the-bias"></section>` with:

```erb
  <%= render "shared/diamond_divider" %>

  <%# === Zone 3: Your Questions, Answered === %>
  <section id="your-questions" class="topic-article-section">
    <div class="home-section-header">
      <%= render "shared/atom_marker" %>
      <span class="section-label">Your Questions</span>
      <span class="section-line"></span>
    </div>

    <dl class="about-faq">
      <div class="about-faq-item">
        <dt class="about-faq-question">"Who's behind this?"</dt>
        <dd class="about-faq-answer">One resident, working independently. Not connected to city hall, not funded by anyone, not affiliated with any political group or candidate. The site costs money to run — that comes out of pocket. No ads, no sponsors.</dd>
      </div>

      <div class="about-faq-item">
        <dt class="about-faq-question">"Who's paying for this?"</dt>
        <dd class="about-faq-answer">Hosting and AI processing — paid by the person who built it. No revenue, no grants, no city funding. If that ever changes, it'll be stated here.</dd>
      </div>

      <div class="about-faq-item">
        <dt class="about-faq-question">"Can I trust what the AI writes?"</dt>
        <dd class="about-faq-answer">The AI reads the same documents you could find on the city's website. It's told to separate what actually happened — votes, motions, dollar amounts — from how the city describes it. Every summary links back to the source so you can read the original yourself. If something looks wrong, check it. That's the whole point.</dd>
      </div>

      <div class="about-faq-item">
        <dt class="about-faq-question">"What doesn't this cover?"</dt>
        <dd class="about-faq-answer">Routine business that doesn't affect your life — license renewals, proclamations, approving last month's minutes, things like that. The site focuses on what hits your taxes, your neighborhood, your streets, your water. If nobody showed up to talk about it and the vote was unanimous on something routine, it probably won't show up here.</dd>
      </div>

      <div class="about-faq-item">
        <dt class="about-faq-question">"Who decides what shows up on the front page?"</dt>
        <dd class="about-faq-answer">Not a person. The system looks at signals: Did people show up to comment? Was the vote close? Does it affect property taxes or zoning? Has it come up at multiple meetings over time? Issues with more of those signals get featured. Issues without them are still on the site — just not on the front page.</dd>
      </div>
    </dl>
  </section>

  <%= render "shared/diamond_divider" %>

  <%# === The Bias (separated for anchor link) === %>
  <section id="the-bias" class="topic-article-section">
    <div class="home-section-header">
      <%= render "shared/atom_marker" %>
      <span class="section-label">The Bias</span>
      <span class="section-line"></span>
    </div>

    <div class="about-faq">
      <p class="about-faq-answer">This site is not neutral and doesn't pretend to be.</p>
      <p class="about-faq-answer">It's built with a point of view: residents deserve to understand what's happening at city hall, and the way the city presents information isn't always the full picture.</p>
      <p class="about-faq-answer">The AI is specifically instructed to question how decisions are framed — not to assume the city's description of something is the whole story. It's also told never to accuse anyone of bad intentions or bad faith. Decisions and processes get questioned. People don't.</p>
      <p class="about-faq-answer">The person who built this site wrote a detailed description of who Two Rivers residents are — what they care about, what's routine, what local governance quirks matter. Those instructions shape how every summary is written. The goal is informed residents, not gotcha journalism, and not a mouthpiece for city hall.</p>
    </div>
  </section>
```

- [ ] **Step 2: Run tests**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: all 4 tests PASS

- [ ] **Step 3: Visually verify in browser**

Visit `/about`. Confirm:
- Diamond divider between Zone 2 and Zone 3
- FAQ items with bold questions, muted answers, generous spacing
- "The Bias" has its own section header and anchor
- Anchor bar links jump to correct sections

- [ ] **Step 4: Commit**

```bash
git add app/views/pages/about.html.erb
git commit -m "feat: About page Zone 3 — FAQ and editorial bias statement"
```

---

### Task 7: Zone 4 — Under the Hood (Technical Deep Dive)

**Files:**
- Modify: `app/views/pages/about.html.erb`

- [ ] **Step 1: Replace the `#under-the-hood` placeholder**

Replace `<section id="under-the-hood"></section>` with:

```erb
  <%= render "shared/diamond_divider" %>

  <%# === Zone 4: Under the Hood === %>
  <section id="under-the-hood" class="topic-article-section">
    <div class="home-section-header">
      <%= render "shared/atom_marker" %>
      <span class="section-label">Under the Hood</span>
      <span class="section-line"></span>
    </div>

    <div class="about-hood-zone">

      <div class="about-hood-section">
        <h3 class="about-hood-heading">How the AI Is Instructed</h3>
        <p>The AI that writes summaries follows written rules about how to handle city documents. Three categories of information are kept separate in every summary:</p>
        <ul>
          <li><strong>What actually happened</strong> — votes, motions, dollar amounts, dates. These come straight from the official record and must be traceable to a specific document.</li>
          <li><strong>How the city describes it</strong> — staff summaries, agenda titles, the language in meeting packets. The AI treats this as the city's perspective, not as neutral truth. When the city's description doesn't match the outcome or the observable impact, the AI notes that.</li>
          <li><strong>What residents seem to care about</strong> — based on who shows up to comment, what keeps coming back meeting after meeting, and how divided the votes are. This is always presented as observation, never as established fact.</li>
        </ul>
        <p>The person who built this site also wrote a detailed description of who Two Rivers residents are — what they care about, what's routine, what local governance quirks matter (like how height-and-area exceptions get used, or why CDA agendas aren't always substantive). Those instructions shape how every summary is written.</p>
      </div>

      <div class="about-hood-section">
        <h3 class="about-hood-heading">How Issues Are Tracked Across Meetings</h3>
        <p>When something like "Lead Service Line Replacement" shows up on an agenda in January, then again in a committee meeting in March, then gets voted on by the Council in June — those are all automatically connected. The system notices when an issue is still being discussed, when it hasn't come up in a while, and when it got a final vote.</p>
        <p>That's how the site can tell you something has been deferred three times, or that an issue reappears every budget cycle. No one is manually connecting those dots — it happens automatically as new documents arrive.</p>
      </div>

      <div class="about-hood-section">
        <h3 class="about-hood-heading">What Gets Filtered Out</h3>
        <p>Summaries skip the procedural business that every meeting has: adjournment motions, approving last meeting's minutes, roll call for remote participation, and truly routine consent agenda items.</p>
        <p>One exception: when the Council goes into closed session, the motion to close <em>is</em> included. Wisconsin law
          (<a href="https://docs.legis.wisconsin.gov/statutes/statutes/19/v/85" target="_blank" rel="noopener">&sect;19.85</a>)
          requires transparency about what gets discussed behind closed doors. Residents should see that.</p>
      </div>

      <div class="about-hood-section">
        <h3 class="about-hood-heading">How It Decides What to Show You First</h3>
        <p>The front page features issues based on automated signals, not anyone's personal judgment. The system weighs:</p>
        <ul>
          <li>Whether residents showed up to speak about it (strongest signal)</li>
          <li>Whether the vote was close or split</li>
          <li>Whether it affects property taxes, zoning, or infrastructure</li>
          <li>Whether it's come up across multiple meetings or committees</li>
          <li>Whether there have been repeated delays or unresolved questions</li>
        </ul>
        <p>No one hand-picks what goes on the front page. An issue about sidewalk repair and an issue about a $2 million TIF district go through the same process — the TIF district shows up higher because it triggers more of those signals.</p>
      </div>

      <div class="about-hood-section">
        <h3 class="about-hood-heading">The Source Documents</h3>
        <p>Every meeting page on this site has a "Documents" section with the original PDFs from the city. The city is required by Wisconsin's Open Meetings Law to make these available to the public. This site saves copies because government websites sometimes reorganize, move pages, or remove old documents.</p>
        <p>Relevant Wisconsin statutes:</p>
        <ul>
          <li><a href="https://docs.legis.wisconsin.gov/statutes/statutes/19/v" target="_blank" rel="noopener">Chapter 19, Subchapter V</a> — Open Meetings Law (full text)</li>
          <li><a href="https://docs.legis.wisconsin.gov/statutes/statutes/19/v/84" target="_blank" rel="noopener">&sect;19.84</a> — Public notice requirements for meetings</li>
          <li><a href="https://docs.legis.wisconsin.gov/statutes/statutes/19/v/88" target="_blank" rel="noopener">&sect;19.88(3)</a> — Minutes must be available for public inspection</li>
        </ul>
      </div>

    </div>
  </section>

</article>

<div class="topic-article-footer">
  <%= link_to "← Home", root_path, class: "btn btn--ghost" %>
</div>
```

- [ ] **Step 2: Run tests**

Run: `bin/rails test test/controllers/pages_controller_test.rb`
Expected: all 4 tests PASS

- [ ] **Step 3: Visually verify in browser**

Visit `/about`. Confirm:
- Diamond divider before Zone 4
- Cool-tinted background on the Under the Hood zone
- Terra cotta uppercase sub-headings
- Three-category list renders clearly
- Wisconsin statute links open in new tabs
- Radar sweep or atom marker decoration visible
- Footer "Home" link works

- [ ] **Step 4: Commit**

```bash
git add app/views/pages/about.html.erb
git commit -m "feat: About page Zone 4 — Under the Hood technical deep dive"
```

---

### Task 8: Visual Polish and Decoration Pass

**Files:**
- Modify: `app/views/pages/about.html.erb` (add boomerang decorations)
- Modify: `app/assets/stylesheets/about.css` (any adjustments from browser testing)

This task is for the decorative and visual polish pass after all content is in place. It should be done while looking at the page in the browser.

- [ ] **Step 1: Add boomerang decorations to Zone 2**

In `about.html.erb`, wrap the Zone 2 section content in a relative-positioned container and add boomerang SVGs. After the `home-section-header` div inside `#how-it-works`, add:

```erb
    <div style="position: relative;">
      <div class="about-boomerang-left">
        <%= render "shared/boomerang", size: 120, opacity: 0.04, rotation: -15 %>
      </div>
```

And close the div after the `</ol>`:

```erb
    </ol>
    </div>
```

- [ ] **Step 2: Add radar sweep to Zone 4 header**

In the Zone 4 section, right after the `home-section-header` div and before the `about-hood-zone` div, add:

```erb
    <div style="position: absolute; right: -20px; top: -10px; pointer-events: none;">
      <%= render "shared/radar_sweep", size: 60, opacity: 0.06 %>
    </div>
```

This is optional — only add if it looks good in the browser. If the zone's `overflow: hidden` clips it or it looks cluttered, skip it.

- [ ] **Step 3: Visually verify full page in browser**

Visit `/about`. Do a full scroll-through on both desktop and mobile widths. Check:
- Decorative elements are subtle, not distracting
- Boomerangs hidden on narrow screens (media query)
- All anchor links scroll to correct sections
- Spacing feels right between all zones
- Typography hierarchy reads clearly
- Cool-toned zone 4 background provides visual shift
- Page loads fast (no heavy images)

- [ ] **Step 4: Adjust CSS as needed**

Make any spacing, sizing, or opacity tweaks found during browser testing. All changes in `about.css`.

- [ ] **Step 5: Run full test suite**

Run: `bin/rails test`
Expected: all tests PASS (no regressions)

- [ ] **Step 6: Run lint**

Run: `bin/rubocop`
Expected: no new offenses

- [ ] **Step 7: Commit**

```bash
git add app/views/pages/about.html.erb app/assets/stylesheets/about.css
git commit -m "feat: About page visual polish — decorative SVGs and spacing refinements"
```

---

### Task 9: Documentation Updates

**Files:**
- Modify: `CLAUDE.md`
- Modify: `config/routes.rb` (comment only — already done in Task 1)

- [ ] **Step 1: Update CLAUDE.md Routes section**

In the Routes section of `CLAUDE.md`, add `/about` to the public routes list. Find the line:

```
Public: `/ (home#index)`, `/meetings`, `/topics`, `/members` (all read-only index+show).
```

Replace with:

```
Public: `/ (home#index)`, `/about`, `/meetings`, `/topics`, `/members` (all read-only index+show).
```

- [ ] **Step 2: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add About page to CLAUDE.md routes"
```
