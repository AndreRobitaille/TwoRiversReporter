# Atomic-Era Design System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current system-font, navy-blue design with an Atomic-era design system featuring two themes (Living Room for public, Silo for admin) using Outfit, Space Grotesk, and DM Mono typography.

**Architecture:** CSS custom properties at `:root` define shared tokens (spacing, radius, shadows, identity colors). Theme-specific neutrals live under `.theme-living-room` and `.theme-silo` classes on `<body>`. The admin layout gets its own layout file to apply the Silo theme. Dark mode is removed entirely.

**Tech Stack:** Plain CSS (no preprocessor), Propshaft, Google Fonts via `<link>`, Rails layouts, SVG motifs as partials.

**Spec:** `docs/plans/2026-03-28-atomic-design-system-spec.md`

---

## File Map

| Action | File | Responsibility |
|--------|------|---------------|
| Modify | `app/views/layouts/application.html.erb` | Add Google Fonts, apply `.theme-living-room`, remove dark mode toggle/script |
| Create | `app/views/layouts/admin.html.erb` | Admin layout applying `.theme-silo` class, admin-specific nav |
| Modify | `app/controllers/admin/base_controller.rb` | Set `layout "admin"` |
| Modify | `app/assets/stylesheets/application.css` | Replace all CSS variables, typography, colors; remove dark mode; add theme classes |
| Create | `app/views/shared/_atom_marker.html.erb` | Atom marker SVG partial (configurable theme) |
| Create | `app/views/shared/_diamond_divider.html.erb` | Diamond divider SVG partial |
| Create | `app/views/shared/_starburst.html.erb` | Starburst SVG partial |
| Create | `app/views/shared/_boomerang.html.erb` | Boomerang SVG partial |
| Create | `app/views/shared/_radar_sweep.html.erb` | Radar sweep SVG partial |
| Modify | `test/system/design_system_test.rb` (create) | System tests verifying theme application |

---

### Task 1: Remove Dark Mode

Dark mode adds complexity to every color decision. Remove it cleanly before changing anything else.

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Remove dark mode JavaScript from layout**

In `app/views/layouts/application.html.erb`, remove the inline `<script>` block in `<head>` that reads `localStorage.getItem('theme')` and sets `data-theme`. Also remove the theme toggle button (sun/moon icons) and the `toggleTheme()`/`updateThemeIcon()` script block at the bottom of `<body>`.

Keep the rest of the header nav (Meetings, Topics, City Officials links) intact.

- [ ] **Step 2: Remove dark mode CSS from application.css**

In `app/assets/stylesheets/application.css`, delete:
- The entire `[data-theme="dark"]` block (all CSS variables inside it)
- The `@media (prefers-color-scheme: dark)` fallback block
- Any `.theme-toggle` or theme-toggle-related CSS rules

Search for `data-theme` and `prefers-color-scheme` to make sure nothing remains.

- [ ] **Step 3: Verify the app loads without errors**

Run: `bin/rails test`

Verify no test references the theme toggle. Start the dev server (`bin/dev`) and confirm pages render with light mode colors only, no JavaScript console errors.

- [ ] **Step 4: Commit**

```bash
git add app/views/layouts/application.html.erb app/assets/stylesheets/application.css
git commit -m "refactor: remove dark mode support

Dark mode is out of scope for the Atomic-era design system.
Removes theme toggle UI, localStorage detection, and all
dark mode CSS variable overrides."
```

---

### Task 2: Add Google Fonts and Replace Typography Tokens

**Files:**
- Modify: `app/views/layouts/application.html.erb`
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add Google Fonts `<link>` tags to the layout**

In `app/views/layouts/application.html.erb`, add these lines inside `<head>`, before the stylesheet link:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;900&family=Space+Grotesk:wght@400;500;600;700&family=DM+Mono:wght@300;400;500&display=swap" rel="stylesheet">
```

- [ ] **Step 2: Replace font-family CSS variables**

In `app/assets/stylesheets/application.css`, find the `:root` block. Replace the font variables:

```css
/* Old */
--font-sans: -apple-system, BlinkMacSystemFont, "Segoe UI", ...;
--font-mono: ui-monospace, SFMono-Regular, ...;

/* New */
--font-display: 'Outfit', sans-serif;
--font-body: 'Space Grotesk', sans-serif;
--font-data: 'DM Mono', monospace;
```

- [ ] **Step 3: Update all `font-family` references in the CSS**

Search `application.css` for every use of `var(--font-sans)` and replace with `var(--font-body)`. Search for `var(--font-mono)` and replace with `var(--font-data)`.

Then update these specific rules:
- `body` selector: `font-family: var(--font-body);`
- All heading selectors (`h1` through `h6`): `font-family: var(--font-display);`
- Any `.page-title`, `.card-title`, stat-number classes: `font-family: var(--font-display);`
- Table `th` elements: `font-family: var(--font-data);`
- Any monospace/code elements: `font-family: var(--font-data);`

- [ ] **Step 4: Start dev server and visually verify fonts load**

Run: `bin/dev`

Open the homepage and an admin page. Verify in browser DevTools:
- Body text renders in Space Grotesk
- Headings render in Outfit
- Table headers and metadata render in DM Mono
- No FOUT (flash of unstyled text) beyond initial load

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/application.html.erb app/assets/stylesheets/application.css
git commit -m "feat: add Outfit, Space Grotesk, DM Mono typography

Replace system font stack with Atomic-era fonts.
Outfit for display/headings, Space Grotesk for body,
DM Mono for data labels and metadata."
```

---

### Task 3: Replace Color Palette with Shared Identity Colors

Replace the current navy/blue palette with the Atomic-era identity colors. This task only changes the `:root` variables — theme-specific neutrals come in Task 4.

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Replace identity color variables in `:root`**

Find the color variables in the `:root` block and replace them:

```css
/* Identity colors — shared across both themes */
--color-teal: #004a59;
--color-terra-cotta: #c2522a;
--color-amber: #d4872a;
--color-forest: #2a7a4a;
--color-brick: #9e2a2a;

/* Map semantic names to identity colors */
--color-primary: var(--color-teal);
--color-primary-hover: #003440;
--color-primary-light: #e0f0f4;
--color-accent: var(--color-terra-cotta);
--color-accent-hover: #a3421f;

--color-success: var(--color-forest);
--color-success-light: #e6f2ee;
--color-warning: var(--color-amber);
--color-warning-light: #fef3e2;
--color-danger: var(--color-brick);
--color-danger-light: #fce8e8;
```

- [ ] **Step 2: Replace accent warm/cool variables**

The current CSS has `--color-accent-warm` and `--color-accent-cool` pairs used for topic cards. Replace:

```css
--color-accent-warm: var(--color-terra-cotta);
--color-accent-warm-light: #fef3e2;
--color-accent-warm-bg: #fffbf5;
--color-accent-warm-hover: #a3421f;

--color-accent-cool: var(--color-teal);
--color-accent-cool-light: #e0f0f4;
--color-accent-cool-bg: #f5fcfd;
--color-accent-cool-hover: #003440;
```

- [ ] **Step 3: Replace header and footer colors**

```css
--color-header-bg: var(--color-teal);
--color-header-text: #ffffff;
--color-header-text-muted: rgba(255, 255, 255, 0.7);
--color-footer-bg: #1a2e35;
--color-footer-text: #cbd5e1;
```

- [ ] **Step 4: Verify pages render with new color palette**

Run: `bin/dev`

Check homepage, topics index, a meeting show page, and admin dashboard. The header should now be deep teal (#004a59) instead of navy. Accents should be terra cotta/amber instead of blue.

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: replace color palette with Atomic-era identity colors

Deep teal, terra cotta, amber, forest green, brick red
replace the navy/blue palette. Semantic color mappings
preserved (primary, success, warning, danger)."
```

---

### Task 4: Add Theme Classes for Living Room and Silo Neutrals

**Files:**
- Modify: `app/assets/stylesheets/application.css`
- Modify: `app/views/layouts/application.html.erb`

- [ ] **Step 1: Move current neutral colors under `.theme-living-room`**

The current `:root` block has neutral variables (`--color-bg`, `--color-surface`, `--color-text`, etc.). Move these out of `:root` and into a `.theme-living-room` block, updating values to the warm cream palette:

```css
.theme-living-room {
  --color-bg: #faf5eb;
  --color-surface: #ffffff;
  --color-surface-raised: #f0e8d8;
  --color-surface-hover: rgba(0, 0, 0, 0.03);
  --color-border: #e0d5c3;
  --color-border-strong: #c8bda8;
  --color-text: #2c2520;
  --color-text-secondary: #6b5e50;
  --color-text-muted: #9a8d7e;
  --color-text-inverse: #ffffff;
}
```

- [ ] **Step 2: Add `.theme-silo` block**

Add after the Living Room block:

```css
.theme-silo {
  --color-bg: #f2f5f5;
  --color-surface: #ffffff;
  --color-surface-raised: #e4eaea;
  --color-surface-hover: rgba(0, 0, 0, 0.03);
  --color-border: #c5d0d0;
  --color-border-strong: #a0b0b0;
  --color-text: #1a2e35;
  --color-text-secondary: #5a7a80;
  --color-text-muted: #8a9fa3;
  --color-text-inverse: #ffffff;
}
```

- [ ] **Step 3: Add `.theme-living-room` class to the public layout body**

In `app/views/layouts/application.html.erb`, change:

```html
<body>
```

to:

```html
<body class="theme-living-room">
```

- [ ] **Step 4: Verify public pages render with warm cream neutrals**

Run: `bin/dev`

Homepage background should now be cream (#faf5eb) instead of the old warm gray. Cards should be white on cream. Text should be espresso brown, not dark gray.

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/application.css app/views/layouts/application.html.erb
git commit -m "feat: add Living Room and Silo theme classes

Move neutral colors into .theme-living-room (warm cream)
and .theme-silo (cool concrete). Apply Living Room to
public layout. Admin layout will apply Silo in next task."
```

---

### Task 5: Create Admin Layout with Silo Theme

Currently admin pages use the shared `application.html.erb` layout. Create a dedicated admin layout that applies the Silo theme.

**Files:**
- Create: `app/views/layouts/admin.html.erb`
- Modify: `app/controllers/admin/base_controller.rb`

- [ ] **Step 1: Read the current application layout and admin base controller**

Read `app/views/layouts/application.html.erb` to understand the current structure. Read `app/controllers/admin/base_controller.rb` to see if a layout is already set.

- [ ] **Step 2: Create the admin layout**

Create `app/views/layouts/admin.html.erb`. Copy the structure from `application.html.erb` but with these changes:
- `<body class="theme-silo">` instead of `theme-living-room`
- Replace the public nav (Meetings, Topics, City Officials) with admin nav links (Dashboard, Topics, Committees, Members, Knowledge Sources, Jobs)
- Keep the same `<head>` contents (meta tags, Google Fonts, stylesheet, importmap)
- Keep the same footer structure but you may simplify the links

The admin nav should use the same header structure (`.site-header`) but with admin-appropriate links.

- [ ] **Step 3: Set the admin layout in the base controller**

In `app/controllers/admin/base_controller.rb`, add (if not already present):

```ruby
layout "admin"
```

- [ ] **Step 4: Verify admin pages render with Silo theme**

Run: `bin/dev`

Navigate to `/admin` (login if needed). The background should be cool concrete (#f2f5f5), borders should be gunmetal, text should be midnight teal. The header should still be deep teal.

Compare a public page (warm cream) next to an admin page (cool concrete) to confirm the theme split is visible.

- [ ] **Step 5: Commit**

```bash
git add app/views/layouts/admin.html.erb app/controllers/admin/base_controller.rb
git commit -m "feat: create admin layout with Silo theme

Admin pages now use dedicated layout with .theme-silo
(cool concrete neutrals) and admin-specific navigation."
```

---

### Task 6: Create SVG Motif Partials

Create reusable Rails partials for each graphic motif so they can be included anywhere with `render`.

**Files:**
- Create: `app/views/shared/_atom_marker.html.erb`
- Create: `app/views/shared/_diamond_divider.html.erb`
- Create: `app/views/shared/_starburst.html.erb`
- Create: `app/views/shared/_boomerang.html.erb`
- Create: `app/views/shared/_radar_sweep.html.erb`

- [ ] **Step 1: Create the atom marker partial**

Create `app/views/shared/_atom_marker.html.erb`:

```erb
<%# Atom marker for section headers. Pass theme: "living-room" or "silo" %>
<% theme = local_assigns.fetch(:theme, "living-room") %>
<% size = local_assigns.fetch(:size, 20) %>
<svg width="<%= size %>" height="<%= size %>" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <defs>
    <ellipse id="atom-orbit-<%= size %>" cx="50" cy="50" rx="38" ry="12" fill="none"
             stroke="<%= theme == 'silo' ? '#004a59' : '#c2522a' %>"
             stroke-width="<%= theme == 'silo' ? '4' : '4' %>"
             opacity="<%= theme == 'silo' ? '0.4' : '1' %>"/>
  </defs>
  <use href="#atom-orbit-<%= size %>" transform="rotate(-30, 50, 50)"/>
  <% if theme != "silo" %>
    <use href="#atom-orbit-<%= size %>" transform="rotate(30, 50, 50)"/>
    <use href="#atom-orbit-<%= size %>" transform="rotate(90, 50, 50)"/>
    <circle cx="15" cy="32" r="5" fill="#c2522a"/>
    <circle cx="78" cy="30" r="5" fill="#c2522a"/>
    <circle cx="50" cy="88" r="5" fill="#c2522a"/>
  <% end %>
  <circle cx="50" cy="50" r="8" fill="#004a59"/>
</svg>
```

- [ ] **Step 2: Create the diamond divider partial**

Create `app/views/shared/_diamond_divider.html.erb`:

```erb
<%# Diamond divider for section breaks. Pass theme: "living-room" or "silo" %>
<% theme = local_assigns.fetch(:theme, "living-room") %>
<% color = theme == "silo" ? "var(--color-border)" : "var(--color-terra-cotta)" %>
<svg class="diamond-divider" width="100%" height="20" viewBox="0 0 300 20" preserveAspectRatio="xMidYMid meet" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
  <line x1="10" y1="10" x2="133" y2="10" stroke="url(#dd-fade-in)" stroke-width="1.5"/>
  <polygon points="150,2 158,10 150,18 142,10" fill="<%= color %>"/>
  <line x1="167" y1="10" x2="290" y2="10" stroke="url(#dd-fade-out)" stroke-width="1.5"/>
  <defs>
    <linearGradient id="dd-fade-in" x1="10" y1="10" x2="133" y2="10">
      <stop stop-color="transparent"/>
      <stop offset="1" stop-color="<%= color %>"/>
    </linearGradient>
    <linearGradient id="dd-fade-out" x1="167" y1="10" x2="290" y2="10">
      <stop stop-color="<%= color %>"/>
      <stop offset="1" stop-color="transparent"/>
    </linearGradient>
  </defs>
</svg>
```

- [ ] **Step 3: Create the starburst partial**

Create `app/views/shared/_starburst.html.erb`:

```erb
<%# Starburst decoration. Living Room only. %>
<% size = local_assigns.fetch(:size, 64) %>
<% opacity = local_assigns.fetch(:opacity, 1.0) %>
<svg width="<%= size %>" height="<%= size %>" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" style="opacity: <%= opacity %>">
  <defs>
    <polygon id="sb-long-ray" points="0,0 2.5,-42 -2.5,-42"/>
    <polygon id="sb-short-ray" points="0,0 1.5,-16 -1.5,-16"/>
  </defs>
  <g transform="translate(50,50)" fill="#c2522a">
    <use href="#sb-long-ray" transform="rotate(0)"/>
    <use href="#sb-long-ray" transform="rotate(90)"/>
    <use href="#sb-long-ray" transform="rotate(180)"/>
    <use href="#sb-long-ray" transform="rotate(270)"/>
    <use href="#sb-short-ray" transform="rotate(45)"/>
    <use href="#sb-short-ray" transform="rotate(135)"/>
    <use href="#sb-short-ray" transform="rotate(225)"/>
    <use href="#sb-short-ray" transform="rotate(315)"/>
    <circle r="5" fill="#004a59"/>
  </g>
</svg>
```

- [ ] **Step 4: Create the boomerang partial**

Create `app/views/shared/_boomerang.html.erb`:

```erb
<%# Boomerang background decoration. Living Room only. %>
<% size = local_assigns.fetch(:size, 100) %>
<% opacity = local_assigns.fetch(:opacity, 0.05) %>
<% rotation = local_assigns.fetch(:rotation, 0) %>
<% color = local_assigns.fetch(:color, "#c2522a") %>
<svg width="<%= size %>" height="<%= (size * 0.78).round %>" viewBox="30 130 950 750" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" style="opacity: <%= opacity %>; transform: rotate(<%= rotation %>deg)">
  <path fill="<%= color %>" d="M600.63,832.33 C567.66,824.68 534.84,818.15 502.63,809.36 C465.90,799.34 429.46,788.06 393.34,775.99 C339.11,757.87 286.55,735.51 235.74,709.22 C190.24,685.68 146.72,658.91 107.16,626.21 C89.99,612.02 72.60,597.78 59.61,579.36 C31.23,539.13 26.15,495.84 44.07,450.04 C51.85,430.14 65.10,414.13 80.55,399.46 C106.87,374.46 135.62,352.70 166.03,333.08 C203.03,309.20 241.88,288.69 281.92,270.37 C330.13,248.31 379.63,229.69 430.09,213.58 C476.38,198.80 523.23,185.96 570.82,176.13 C602.86,169.50 635.06,163.50 667.35,158.15 C691.92,154.08 716.70,151.15 741.45,148.33 C758.95,146.34 776.55,145.08 794.13,144.06 C815.72,142.81 837.34,141.55 858.95,141.38 C886.38,141.17 913.93,140.93 940.77,148.05 C946.96,149.69 953.16,152.12 958.68,155.35 C968.18,160.91 970.53,169.81 966.07,179.91 C960.55,192.42 951.23,201.98 941.18,210.79 C900.91,246.09 855.09,273.41 809.87,301.57 C747.28,340.57 684.38,379.06 622.13,418.59 C595.01,435.80 569.79,455.69 546.73,478.38 C520.68,504.01 519.30,539.45 531.41,567.91 C542.58,594.15 561.29,614.62 582.32,633.09 C621.50,667.52 665.99,694.01 712.21,717.55 C750.48,737.05 789.36,755.36 828.08,773.99 C858.84,788.78 889.89,802.99 920.53,818.02 C930.04,822.68 938.65,829.15 947.66,834.82 C948.50,835.35 949.27,836.01 950.00,836.68 C958.04,844.16 957.18,850.64 946.72,853.86 C938.06,856.52 928.88,858.15 919.84,858.74 C901.08,859.96 882.24,861.12 863.47,860.60 C829.89,859.68 796.28,858.39 762.81,855.64 C711.28,851.42 660.14,843.90 609.37,834.02 C606.60,833.48 603.82,832.97 600.63,832.33 Z"/>
</svg>
```

- [ ] **Step 5: Create the radar sweep partial**

Create `app/views/shared/_radar_sweep.html.erb`:

```erb
<%# Radar sweep background decoration. Silo only. %>
<% size = local_assigns.fetch(:size, 80) %>
<% opacity = local_assigns.fetch(:opacity, 0.08) %>
<svg width="<%= size %>" height="<%= size %>" viewBox="0 0 100 100" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true" style="opacity: <%= opacity %>">
  <circle cx="50" cy="50" r="36" stroke="#004a59" stroke-width="1"/>
  <circle cx="50" cy="50" r="24" stroke="#004a59" stroke-width="1"/>
  <circle cx="50" cy="50" r="12" stroke="#004a59" stroke-width="1"/>
  <line x1="50" y1="50" x2="50" y2="14" stroke="#004a59" stroke-width="1.5"/>
  <path d="M50 50 L50 14 A36 36 0 0 1 80 32 Z" fill="#004a59" opacity="0.5"/>
  <circle cx="50" cy="50" r="3" fill="#004a59"/>
</svg>
```

- [ ] **Step 6: Commit**

```bash
git add app/views/shared/_atom_marker.html.erb \
        app/views/shared/_diamond_divider.html.erb \
        app/views/shared/_starburst.html.erb \
        app/views/shared/_boomerang.html.erb \
        app/views/shared/_radar_sweep.html.erb
git commit -m "feat: add SVG motif partials for Atomic-era design

Atom marker (both themes), diamond divider (both),
starburst (Living Room), boomerang (Living Room),
radar sweep (Silo). All accept size/opacity/theme locals."
```

---

### Task 7: Add Section Header Component CSS

The atom-marker section header pattern is used across both themes. Add the CSS class and demonstrate usage.

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add section header CSS**

Add to `application.css` (near the existing page-header styles):

```css
/* Section headers — atom marker + label + trailing line */
.section-header {
  display: flex;
  align-items: center;
  gap: var(--space-3);
  margin-bottom: var(--space-4);
}

.section-header__label {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-teal);
  white-space: nowrap;
}

.section-header__line {
  flex: 1;
  height: 1px;
}

.theme-living-room .section-header__line {
  background: linear-gradient(to right, var(--color-terra-cotta), transparent);
}

.theme-silo .section-header__line {
  background: linear-gradient(to right, var(--color-border), transparent);
}
```

- [ ] **Step 2: Verify with dev server**

Run `bin/dev`. The CSS should parse without errors. Actual usage of the section header pattern comes when views are updated — this just establishes the CSS classes.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: add section header component CSS

Atom marker + label + trailing gradient line pattern
for both Living Room and Silo themes."
```

---

### Task 8: Update Status Chip / Badge CSS

Update the existing badge CSS to use DM Mono and the new semantic colors with theme-aware borders.

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Update badge CSS**

Find the existing `.badge` styles in `application.css` and update them:

```css
.badge {
  display: inline-flex;
  align-items: center;
  padding: var(--space-1) var(--space-2);
  font-family: var(--font-data);
  font-size: var(--text-xs);
  font-weight: 500;
  text-transform: uppercase;
  letter-spacing: 0.06em;
  border-radius: var(--radius-full);
  line-height: 1;
}

/* Silo chips get a subtle border for crispness */
.theme-silo .badge {
  border: 1px solid transparent;
}

.badge--default {
  background: var(--color-surface-raised);
  color: var(--color-text-secondary);
}
.theme-silo .badge--default {
  border-color: var(--color-border);
}

.badge--primary {
  background: var(--color-primary-light);
  color: var(--color-primary);
}
.theme-silo .badge--primary {
  border-color: #b0d0d8;
}

.badge--success {
  background: var(--color-success-light);
  color: var(--color-success);
}
.theme-silo .badge--success {
  border-color: #b5d5cf;
}

.badge--warning {
  background: var(--color-warning-light);
  color: var(--color-warning);
}
.theme-silo .badge--warning {
  border-color: #f0d9b5;
}

.badge--danger {
  background: var(--color-danger-light);
  color: var(--color-danger);
}
.theme-silo .badge--danger {
  border-color: #f0c5c5;
}
```

- [ ] **Step 2: Verify badges render in both themes**

Run `bin/dev`. Check a page with badges (e.g., admin topics show page, or knowledge sources index). Badges should now use DM Mono font, uppercase, with the new semantic colors.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: update badge/chip CSS for Atomic design system

DM Mono font, uppercase tracking, semantic colors.
Silo theme adds subtle borders for crispness."
```

---

### Task 9: Update Button CSS

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Update button CSS to use new tokens**

Find the existing `.btn` styles and update them to use the new font and color tokens:

```css
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  gap: var(--space-2);
  padding: var(--space-2) var(--space-4);
  font-family: var(--font-body);
  font-size: var(--text-sm);
  font-weight: 500;
  border: 1px solid transparent;
  border-radius: var(--radius-md);
  cursor: pointer;
  text-decoration: none;
  transition: all var(--transition-fast);
  line-height: 1;
}

.btn--primary {
  background: var(--color-teal);
  color: var(--color-text-inverse);
  border-color: var(--color-teal);
}
.btn--primary:hover {
  background: var(--color-primary-hover);
  border-color: var(--color-primary-hover);
}

.btn--secondary {
  background: var(--color-surface);
  color: var(--color-teal);
  border-color: var(--color-border);
}
.btn--secondary:hover {
  background: var(--color-surface-raised);
  border-color: var(--color-border-strong);
}

.btn--danger {
  background: var(--color-brick);
  color: var(--color-text-inverse);
  border-color: var(--color-brick);
}
.btn--danger:hover {
  background: #861f1f;
  border-color: #861f1f;
}

.btn--ghost {
  background: transparent;
  color: var(--color-text-secondary);
}
.btn--ghost:hover {
  background: var(--color-surface-hover);
  color: var(--color-text);
}
```

- [ ] **Step 2: Verify buttons in both themes**

Run `bin/dev`. Check admin pages (which have various button types) and public pages. Buttons should use Space Grotesk and the new teal/terra-cotta/brick colors.

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: update button CSS for Atomic design system

Space Grotesk font, teal primary, brick danger,
updated hover states for both themes."
```

---

### Task 10: Update Card, Table, and Form CSS

Batch update remaining core components to use the design system tokens.

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Update card CSS**

Find existing `.card` styles and ensure they use the token variables:

```css
.card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-radius: var(--radius-lg);
  padding: var(--space-6);
  box-shadow: var(--shadow-sm);
  transition: box-shadow var(--transition-normal);
}

.card:hover {
  box-shadow: var(--shadow-md);
}

.card--narrow {
  max-width: 800px;
  margin: 0 auto;
}

.card-title {
  font-family: var(--font-display);
  font-weight: 700;
}
```

- [ ] **Step 2: Update table CSS**

Ensure table headers use DM Mono:

```css
.table-wrapper th {
  background: var(--color-surface-raised);
  font-family: var(--font-data);
  font-weight: 500;
  font-size: var(--text-xs);
  color: var(--color-text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.05em;
}

.table-wrapper tbody tr:hover {
  background: var(--color-primary-light);
}
```

- [ ] **Step 3: Update form CSS**

Ensure form inputs use the body font and new focus colors:

```css
.form-input,
.form-select,
.form-textarea {
  font-family: var(--font-body);
  border-color: var(--color-border);
  background: var(--color-surface);
  color: var(--color-text);
}

.form-input:focus-visible,
.form-select:focus-visible,
.form-textarea:focus-visible {
  border-color: var(--color-teal);
  box-shadow: 0 0 0 3px var(--color-primary-light);
}

.form-label {
  font-family: var(--font-body);
  font-weight: 500;
  font-size: var(--text-sm);
}
```

- [ ] **Step 4: Update page header CSS**

```css
.page-title {
  font-family: var(--font-display);
  font-weight: 900;
  text-transform: uppercase;
  letter-spacing: -0.02em;
}

.page-subtitle {
  font-family: var(--font-body);
  color: var(--color-text-secondary);
}
```

- [ ] **Step 5: Verify all components**

Run `bin/dev`. Walk through:
- Homepage (cards, page header)
- Topics index (cards, badges)
- A meeting show page (tables, cards)
- Admin dashboard (cards, links)
- Admin topic edit (forms, buttons)

Everything should use the new fonts and colors consistently.

- [ ] **Step 6: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: update card, table, form, page-header CSS

All core components now use Atomic design system tokens:
display font for headings, data font for table headers,
body font for forms, new border and focus colors."
```

---

### Task 11: Add Attention Card and Nav Grid Components (Silo)

Add the two admin-specific component patterns from the spec.

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Add attention card CSS**

```css
/* Attention cards — left-border accent for items needing action */
.attention-card {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-left: 4px solid var(--color-terra-cotta);
  border-radius: var(--radius-md);
  padding: var(--space-4) var(--space-5);
  cursor: pointer;
  transition: box-shadow var(--transition-normal);
}

.attention-card:hover {
  box-shadow: var(--shadow-md);
}

.attention-card--warning {
  border-left-color: var(--color-amber);
}

.attention-card__title {
  font-family: var(--font-display);
  font-weight: 600;
  font-size: var(--text-base);
  color: var(--color-teal);
}

.attention-card__meta {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  color: var(--color-text-secondary);
  text-transform: uppercase;
  letter-spacing: 0.06em;
  margin-top: var(--space-1);
}

.attention-card__action {
  font-family: var(--font-body);
  font-size: var(--text-sm);
  font-weight: 600;
  color: var(--color-terra-cotta);
  text-decoration: none;
}

.attention-card--warning .attention-card__action {
  color: var(--color-amber);
}
```

- [ ] **Step 2: Add nav grid CSS**

```css
/* Admin nav grid — color-coded stat cards */
.nav-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(140px, 1fr));
  gap: var(--space-3);
}

.nav-grid__item {
  background: var(--color-surface);
  border: 1px solid var(--color-border);
  border-bottom: 3px solid var(--color-teal);
  border-radius: var(--radius-md);
  padding: var(--space-4);
  text-align: center;
  text-decoration: none;
  cursor: pointer;
  transition: box-shadow var(--transition-normal);
}

.nav-grid__item:hover {
  box-shadow: var(--shadow-md);
}

.nav-grid__item--attention {
  border-bottom-color: var(--color-terra-cotta);
}

.nav-grid__item--operations {
  border-bottom-color: var(--color-forest);
}

.nav-grid__item--warning {
  border-bottom-color: var(--color-amber);
}

.nav-grid__count {
  font-family: var(--font-display);
  font-weight: 700;
  font-size: var(--text-2xl);
  color: var(--color-teal);
}

.nav-grid__label {
  font-family: var(--font-data);
  font-size: var(--text-xs);
  text-transform: uppercase;
  letter-spacing: 0.08em;
  color: var(--color-text-secondary);
}
```

- [ ] **Step 3: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "feat: add attention card and nav grid component CSS

Attention cards (left-border accent) and nav grid
(color-coded stat cards) for the Silo admin theme."
```

---

### Task 12: Clean Up Remaining Hardcoded Colors and Old Variables

Sweep through the CSS for any remaining hardcoded hex values or references to old variable names that weren't caught in earlier tasks.

**Files:**
- Modify: `app/assets/stylesheets/application.css`

- [ ] **Step 1: Search for hardcoded hex values**

Search `application.css` for hex color patterns (`#[0-9a-fA-F]`) that aren't inside a CSS variable definition (i.e., not after `--color-`). Replace any found with the appropriate variable reference.

Common ones to watch for:
- `#1a4480` (old navy) → `var(--color-teal)`
- `#0076d6` (old accent blue) → `var(--color-terra-cotta)` or `var(--color-teal)` depending on context
- `#2c3e50` (old footer) → `var(--color-footer-bg)` or the defined footer value
- `#f5f3ef` (old bg) → `var(--color-bg)`

- [ ] **Step 2: Search for old variable names**

Search for any remaining references to `--font-sans` or `--font-mono` and replace with `--font-body` / `--font-data`.

- [ ] **Step 3: Run the full CI suite**

Run: `bin/ci`

This runs RuboCop, bundler-audit, importmap audit, and Brakeman. Fix any issues.

- [ ] **Step 4: Run the test suite**

Run: `bin/rails test`

Fix any test failures related to the layout changes (e.g., system tests that assert on removed theme toggle elements).

- [ ] **Step 5: Commit**

```bash
git add app/assets/stylesheets/application.css
git commit -m "refactor: clean up remaining hardcoded colors and old variables

Replace all remaining hex values with CSS variable references.
Remove stale font variable names."
```

---

### Task 13: Update CLAUDE.md and Close Issue

Update project documentation to reflect the new design system.

**Files:**
- Modify: `CLAUDE.md`

- [ ] **Step 1: Update CLAUDE.md**

In the Tech Stack section, add after "Propshaft":

```
- Atomic-era design system with two themes: Living Room (public) and Silo (admin)
- Typography: Outfit (display), Space Grotesk (body), DM Mono (data) via Google Fonts
```

In the Conventions section, add:

```
- **Design system** — All colors via CSS custom properties, never hardcoded hex. Two themes: `.theme-living-room` (public, warm cream) and `.theme-silo` (admin, cool concrete). Spec at `docs/plans/2026-03-28-atomic-design-system-spec.md`.
- **SVG motifs** — Reusable partials in `app/views/shared/` (`_atom_marker`, `_diamond_divider`, `_starburst`, `_boomerang`, `_radar_sweep`). Atom marker and diamond divider used in both themes; starburst/boomerang/orbital rings are Living Room only; radar sweep is Silo only.
- **Typography roles** — Outfit (display: headings, stats, nav labels, always uppercase), Space Grotesk (body: paragraphs, buttons, forms), DM Mono (data: metadata, timestamps, status chips, always uppercase with wide tracking).
```

- [ ] **Step 2: Commit and close issue**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md with Atomic design system conventions

Add design system details to tech stack and conventions:
two themes, typography roles, SVG motif partials, CSS
variable requirements.

Closes #84"
```

---

## Execution Notes

- **Tasks 1–5 must be sequential** — each builds on the previous. Task 1 (remove dark mode) must come first to avoid conflicts.
- **Task 6 (SVG partials) is independent** — can run in parallel with Tasks 7–11.
- **Tasks 7–11 can be done in any order** — they modify different sections of the CSS.
- **Task 12 (cleanup) must come after all CSS changes** — it's the sweep pass.
- **Task 13 must come last** — documentation after implementation.
