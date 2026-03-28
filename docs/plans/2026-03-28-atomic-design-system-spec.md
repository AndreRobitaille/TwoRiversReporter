# Atomic-Era Design System Spec

**Issue:** #84
**Status:** Design approved
**Scope:** Site-wide design system; admin pages first application

## Design Philosophy

Two Rivers Reporter's visual identity draws from Atomic Age design (1950s–60s post-war optimism) — Lustron houses, Formica countertops, Franciscan dinnerware, Googie architecture. The aesthetic conveys warmth and hope about the future, wrapping civic watchdog tooling in the visual language of a mid-century living room.

The system has **two themes** built on a shared foundation:

- **Living Room** (public pages) — warm, optimistic, inviting. The family gathered around the Philco Predicta, dad reading the newspaper. Full decorative vocabulary.
- **Silo** (admin pages) — the Titan missile silo aesthetic. Serious infrastructure underneath the community. Deep teal dominance, minimal decoration, command-center efficiency.

Same design tokens (spacing, typography scale, radius, shadows). Different color palettes and decorative intensity.

**No dark mode.** Single light theme per context.

---

## Color Palette

### Shared Identity Colors

Used across both themes. These define the brand.

| Token | Hex | Usage |
|-------|-----|-------|
| `--color-teal` | `#004a59` | Primary headings, links, nav chrome |
| `--color-terra-cotta` | `#c2522a` | Accent, action, section labels, attention |
| `--color-amber` | `#d4872a` | Warnings, active states, highlights |
| `--color-forest` | `#2a7a4a` | Success states |
| `--color-brick` | `#9e2a2a` | Danger, errors, destructive actions |

### Living Room Neutrals

Warm cream/sand tones. The Lustron interior.

| Token | Hex | Usage |
|-------|-----|-------|
| `--color-bg` | `#faf5eb` | Page background |
| `--color-surface` | `#ffffff` | Card/panel surface |
| `--color-surface-raised` | `#f0e8d8` | Raised elements, table headers |
| `--color-border` | `#e0d5c3` | Default borders |
| `--color-border-strong` | `#c8bda8` | Emphasized borders |
| `--color-text` | `#2c2520` | Body text (espresso) |
| `--color-text-secondary` | `#6b5e50` | Secondary text (driftwood) |
| `--color-text-muted` | `#9a8d7e` | Muted text, placeholders |

### Silo Neutrals

Cool concrete/steel tones. The command center.

| Token | Hex | Usage |
|-------|-----|-------|
| `--color-bg` | `#f2f5f5` | Page background (concrete) |
| `--color-surface` | `#ffffff` | Card/panel surface |
| `--color-surface-raised` | `#e4eaea` | Raised elements (steel) |
| `--color-border` | `#c5d0d0` | Default borders (gunmetal) |
| `--color-border-strong` | `#a0b0b0` | Emphasized borders |
| `--color-text` | `#1a2e35` | Body text (midnight teal) |
| `--color-text-secondary` | `#5a7a80` | Secondary text (patina) |
| `--color-text-muted` | `#8a9fa3` | Muted text, placeholders |

### Semantic Color Tokens

Same names in both themes, mapped to identity colors with theme-appropriate light backgrounds:

| Token | Value | Usage |
|-------|-------|-------|
| `--color-success` | `--color-forest` | Success badges, confirmations |
| `--color-success-light` | `#e6f2ee` (Living) / `#dcecea` (Silo) | Success badge backgrounds |
| `--color-warning` | `--color-amber` | Warning states |
| `--color-warning-light` | `#fef3e2` | Warning badge backgrounds |
| `--color-danger` | `--color-brick` | Error states, destructive actions |
| `--color-danger-light` | `#fce8e8` | Danger badge backgrounds |
| `--color-info` | `--color-teal` | Informational states |
| `--color-info-light` | `#e0f0f4` | Info badge backgrounds |

---

## Typography

### Font Stack

| Role | Font | Source | Fallback |
|------|------|--------|----------|
| **Display** | Outfit | Google Fonts (variable, 100–900) | sans-serif |
| **Body** | Space Grotesk | Google Fonts (300–700) | sans-serif |
| **Data** | DM Mono | Google Fonts (300, 400, 500) | monospace |

### Font Tokens

```
--font-display: 'Outfit', sans-serif
--font-body: 'Space Grotesk', sans-serif
--font-data: 'DM Mono', monospace
```

### Type Scale

| Token | Size | Typical Font | Usage |
|-------|------|-------------|-------|
| `--text-4xl` | 2.25rem (36px) | Display | Hero stats, page titles |
| `--text-3xl` | 1.875rem (30px) | Display | Section titles |
| `--text-2xl` | 1.5rem (24px) | Display | Card headings |
| `--text-xl` | 1.25rem (20px) | Display/Body | Subheadings |
| `--text-lg` | 1.125rem (18px) | Body | Lead paragraphs |
| `--text-base` | 1rem (16px) | Body | Body text |
| `--text-sm` | 0.875rem (14px) | Body/Data | Secondary text, buttons |
| `--text-xs` | 0.75rem (12px) | Data | Labels, metadata, timestamps |

### Display Usage Rules

- **Outfit** is always uppercase with tight tracking (`letter-spacing: -0.02em` at 4xl/3xl, `0.06–0.08em` at xs/sm labels)
- Weight 900 for hero numbers and page titles, 700 for section headers and card titles
- Never used for body paragraphs

### Body Usage Rules

- **Space Grotesk** for all readable text — paragraphs, buttons, form labels, UI chrome
- Weight 400 for body, 500 for buttons, 600 for emphasized text, 700 for bold
- Line height: 1.5 for body, 1.625 for long-form prose

### Data Usage Rules

- **DM Mono** for metadata labels, timestamps, technical values, status text
- Typically uppercase with wide tracking (`letter-spacing: 0.08–0.12em`)
- Weight 300 for subtle labels, 400 for standard, 500 for emphasized
- Used in status chips, table metadata, pipeline indicators

---

## Graphic Motifs

Six decorative elements drawn from Atomic-era design. Each has a theme assignment controlling where it appears.

### Boomerang

**Theme:** Living Room only
**Source:** Formica Skylark (1951) pattern
**Shape:** Fat, asymmetric crescent/swoosh — wide rounded back, two arms curving inward with tapered tips. Not a V, not a bird, not a kidney bean.

**SVG path data** (in a `0 0 1000 1000` viewBox):

```svg
<path d="M600.63,832.33 C567.66,824.68 534.84,818.15 502.63,809.36
  C465.90,799.34 429.46,788.06 393.34,775.99 C339.11,757.87 286.55,735.51
  235.74,709.22 C190.24,685.68 146.72,658.91 107.16,626.21
  C89.99,612.02 72.60,597.78 59.61,579.36 C31.23,539.13 26.15,495.84
  44.07,450.04 C51.85,430.14 65.10,414.13 80.55,399.46
  C106.87,374.46 135.62,352.70 166.03,333.08 C203.03,309.20 241.88,288.69
  281.92,270.37 C330.13,248.31 379.63,229.69 430.09,213.58
  C476.38,198.80 523.23,185.96 570.82,176.13 C602.86,169.50 635.06,163.50
  667.35,158.15 C691.92,154.08 716.70,151.15 741.45,148.33
  C758.95,146.34 776.55,145.08 794.13,144.06 C815.72,142.81 837.34,141.55
  858.95,141.38 C886.38,141.17 913.93,140.93 940.77,148.05
  C946.96,149.69 953.16,152.12 958.68,155.35 C968.18,160.91 970.53,169.81
  966.07,179.91 C960.55,192.42 951.23,201.98 941.18,210.79
  C900.91,246.09 855.09,273.41 809.87,301.57 C747.28,340.57 684.38,379.06
  622.13,418.59 C595.01,435.80 569.79,455.69 546.73,478.38
  C520.68,504.01 519.30,539.45 531.41,567.91 C542.58,594.15 561.29,614.62
  582.32,633.09 C621.50,667.52 665.99,694.01 712.21,717.55
  C750.48,737.05 789.36,755.36 828.08,773.99 C858.84,788.78 889.89,802.99
  920.53,818.02 C930.04,822.68 938.65,829.15 947.66,834.82
  C948.50,835.35 949.27,836.01 950.00,836.68 C958.04,844.16 957.18,850.64
  946.72,853.86 C938.06,856.52 928.88,858.15 919.84,858.74
  C901.08,859.96 882.24,861.12 863.47,860.60 C829.89,859.68 796.28,858.39
  762.81,855.64 C711.28,851.42 660.14,843.90 609.37,834.02
  C606.60,833.48 603.82,832.97 600.63,832.33 Z"/>
```

**Usage:**
- Background decoration at 4–6% opacity
- Scattered at random rotations, varying sizes
- Never as a standalone icon, button, or focal element
- Pairs with scattered dots between instances

### Starburst

**Theme:** Living Room only
**Source:** Franciscan Starburst dinnerware (1954)
**Shape:** 8-point star with alternating long cardinal rays and short diagonal rays. Needle-thin rays tapering to sharp points. Center nucleus dot.

**SVG construction:**

```svg
<svg viewBox="0 0 100 100">
  <defs>
    <polygon id="long-ray" points="0,0 2.5,-42 -2.5,-42"/>
    <polygon id="short-ray" points="0,0 1.5,-16 -1.5,-16"/>
  </defs>
  <g transform="translate(50,50)">
    <use href="#long-ray" transform="rotate(0)"/>
    <use href="#long-ray" transform="rotate(90)"/>
    <use href="#long-ray" transform="rotate(180)"/>
    <use href="#long-ray" transform="rotate(270)"/>
    <use href="#short-ray" transform="rotate(45)"/>
    <use href="#short-ray" transform="rotate(135)"/>
    <use href="#short-ray" transform="rotate(225)"/>
    <use href="#short-ray" transform="rotate(315)"/>
    <circle r="5"/>
  </g>
</svg>
```

**Usage:**
- Hero sections, page headers, feature callouts
- Can be used as a decorative accent at medium opacity
- Typically terra cotta rays with teal nucleus

### Atom Marker

**Theme:** Both
**Shape:** Central nucleus dot + 3 elliptical orbits at ~60° intervals + electron dots on orbits.

**SVG construction:**

```svg
<svg viewBox="0 0 100 100">
  <defs>
    <ellipse id="orbit" cx="50" cy="50" rx="38" ry="12"
             fill="none" stroke="currentColor" stroke-width="1.5"/>
  </defs>
  <use href="#orbit" transform="rotate(-30, 50, 50)"/>
  <use href="#orbit" transform="rotate(30, 50, 50)"/>
  <use href="#orbit" transform="rotate(90, 50, 50)"/>
  <circle cx="50" cy="50" r="5"/>
  <circle cx="15" cy="32" r="3"/>
  <circle cx="78" cy="30" r="3"/>
  <circle cx="50" cy="88" r="3"/>
</svg>
```

**Usage:**
- Section header marker (simplified: nucleus + single orbit for inline use)
- Living Room: terra cotta orbits, teal nucleus
- Silo: teal orbits at 40% opacity, teal nucleus (no electron dots)
- Always paired with uppercase section label + trailing gradient line

### Diamond Divider

**Theme:** Both
**Shape:** Horizontal gradient line with a small rotated rhombus at center.

**SVG construction:**

```svg
<svg viewBox="0 0 300 20">
  <line x1="10" y1="10" x2="133" y2="10" stroke="url(#fade-in)" stroke-width="1.5"/>
  <polygon points="150,2 158,10 150,18 142,10" fill="currentColor"/>
  <line x1="167" y1="10" x2="290" y2="10" stroke="url(#fade-out)" stroke-width="1.5"/>
</svg>
```

**Usage:**
- Section breaks and content dividers
- Living Room: terra cotta
- Silo: gunmetal border color

### Orbital Rings

**Theme:** Living Room only
**Shape:** 3 faded concentric ellipses at staggered rotation angles.

**Usage:**
- Large-scale background texture for hero sections and empty areas
- 8–15% opacity, teal stroke
- Never in data-dense areas

### Radar Sweep

**Theme:** Silo only
**Shape:** Concentric circles (3 rings) + radial line + translucent sweep arc from center.

**Usage:**
- Dashboard headers, monitoring/status sections
- Teal at low opacity (6–15%)
- Replaces orbital rings as the Silo's signature background motif

### Scattered Dots

**Theme:** Living Room only
**Shape:** Clusters of 2–5 circles at varying radii (1–4px), in teal and terra cotta.

**Usage:**
- Fill gaps between larger motifs (boomerangs, starbursts)
- Not random — intentional clusters suggesting atomic particles
- 5–8% opacity

---

## Component Patterns

### Section Headers

Atom marker + uppercase Outfit label + trailing gradient line.

```
[atom] SECTION TITLE ————————————————
```

- Living Room: terra cotta orbit, teal nucleus, terra cotta gradient line
- Silo: teal orbit (40% opacity), teal nucleus, gunmetal gradient line
- Font: Outfit 700, `--text-xs`, uppercase, `letter-spacing: 0.08em`

### Status Chips

Pill-shaped badges with semantic background colors.

- Font: DM Mono 500, `--text-xs`, uppercase, `letter-spacing: 0.06em`
- Padding: 4px 12px, full border radius
- Living Room: filled background, no border
- Silo: filled background + 1px border for extra crispness against cool backgrounds

### Attention Cards

Left-border accent cards for items needing action (Silo theme primarily).

- 4px left border in terra cotta (attention) or amber (warning)
- Title: Outfit 600, `--text-base`, teal
- Metadata: DM Mono, `--text-xs`, uppercase, secondary text color
- Action link: Space Grotesk 600, `--text-sm`, terra cotta/amber, right-aligned
- Hover: elevate shadow (sm → md)

### Admin Nav Grid

Color-coded stat cards for dashboard navigation (Silo).

- 3px bottom border, color-coded by category (teal=content, terra cotta=attention, green=operations, amber=warnings)
- Large stat number: Outfit 700, `--text-2xl`, teal
- Label: DM Mono, `--text-xs`, uppercase, secondary text color
- Hover: elevate shadow
- Grid layout: `repeat(auto-fill, minmax(140px, 1fr))`

### Buttons

- Font: Space Grotesk
- Primary: teal background, white text
- Secondary: surface background, border, teal text
- Danger: brick red background, white text
- Ghost: transparent, secondary text color
- Sizes: sm (Space-1 / Space-3 padding), md (Space-2 / Space-4), lg (Space-3 / Space-6)

### Cards

- Background: `--color-surface`
- Border: 1px `--color-border`
- Radius: `--radius-lg` (10px)
- Padding: Space-6 (24px)
- Shadow: `--shadow-sm` at rest, `--shadow-md` on hover
- Narrow variant: max-width 800px, centered

### Tables

- Wrapper: overflow-x scroll, border, `--radius-lg`
- Header: `--color-surface-raised` background
- Header text: DM Mono, `--text-xs`, uppercase, `letter-spacing: 0.05em`, secondary text color
- Row hover: `--color-info-light` background
- Cell padding: Space-3 vertical, Space-4 horizontal

### Forms

- Labels: Space Grotesk 500, `--text-sm`
- Inputs: full width, Space-2/Space-3 padding, `--radius-md` border
- Focus: teal border + 3px teal-light box-shadow
- Groups: Space-4 gap between label and input, Space-6 between groups

### Badges

- Font: DM Mono 500, `--text-xs`, uppercase
- Padding: Space-1 / Space-2
- Radius: `--radius-full`
- Semantic variants: success, warning, danger, info, default

### Modals

- Overlay: rgba(0, 0, 0, 0.5)
- Panel: `--color-surface`, max-width 500px, `--radius-lg`
- Max-height: 90vh with overflow-y scroll

### Flash Messages

- Padding: Space-3 / Space-4
- Radius: `--radius-md`
- Variants use semantic color backgrounds and borders

---

## Spacing

4px base unit. Shared across both themes.

| Token | Value | Usage |
|-------|-------|-------|
| `--space-1` | 0.25rem (4px) | Tight gaps, chip padding |
| `--space-2` | 0.5rem (8px) | Input padding, badge padding |
| `--space-3` | 0.75rem (12px) | Form group gaps, table cell padding |
| `--space-4` | 1rem (16px) | Standard gap between elements |
| `--space-6` | 1.5rem (24px) | Card padding, section gaps |
| `--space-8` | 2rem (32px) | Major section margins |
| `--space-12` | 3rem (48px) | Page section spacing |
| `--space-16` | 4rem (64px) | Hero spacing |

---

## Radius & Shadows

### Border Radius

| Token | Value | Usage |
|-------|-------|-------|
| `--radius-sm` | 4px | Inputs, small elements, chips |
| `--radius-md` | 6px | Buttons, badges |
| `--radius-lg` | 10px | Cards, panels |
| `--radius-full` | 9999px | Status dots, pills |

### Shadows

| Token | Value | Usage |
|-------|-------|-------|
| `--shadow-sm` | `0 1px 2px rgba(0,0,0,0.05)` | Cards at rest |
| `--shadow-md` | `0 4px 6px rgba(0,0,0,0.08)` | Cards on hover, dropdowns |
| `--shadow-lg` | `0 10px 15px rgba(0,0,0,0.1)` | Modals, elevated panels |

### Transitions

| Token | Value | Usage |
|-------|-------|-------|
| `--transition-fast` | 150ms ease | Button hovers, input focus |
| `--transition-normal` | 200ms ease | Card hover elevation, general |

---

## Layout

| Token | Value | Notes |
|-------|-------|-------|
| `--layout-max-width` | 1200px | Main content container |
| `--layout-narrow` | 800px | Forms, focused content (`.card--narrow`) |
| `--layout-nav-height` | 64px | Sticky navigation bar |
| `--layout-content-padding` | 24px | Container horizontal padding |

---

## CSS Architecture

### Theme Application

Theme class on `<body>` determines which neutral palette is active:

```html
<!-- Public pages -->
<body class="theme-living-room">

<!-- Admin pages -->
<body class="theme-silo">
```

### Variable Structure

```css
/* Shared identity colors at :root */
:root {
  --color-teal: #004a59;
  --color-terra-cotta: #c2522a;
  --color-amber: #d4872a;
  --color-forest: #2a7a4a;
  --color-brick: #9e2a2a;

  /* Typography */
  --font-display: 'Outfit', sans-serif;
  --font-body: 'Space Grotesk', sans-serif;
  --font-data: 'DM Mono', monospace;

  /* Spacing, radius, shadows, layout — same for both themes */
}

/* Theme-specific neutrals */
.theme-living-room {
  --color-bg: #faf5eb;
  --color-surface: #ffffff;
  --color-surface-raised: #f0e8d8;
  --color-border: #e0d5c3;
  --color-border-strong: #c8bda8;
  --color-text: #2c2520;
  --color-text-secondary: #6b5e50;
  --color-text-muted: #9a8d7e;
}

.theme-silo {
  --color-bg: #f2f5f5;
  --color-surface: #ffffff;
  --color-surface-raised: #e4eaea;
  --color-border: #c5d0d0;
  --color-border-strong: #a0b0b0;
  --color-text: #1a2e35;
  --color-text-secondary: #5a7a80;
  --color-text-muted: #8a9fa3;
}
```

### File Structure

Single `application.css` file. No preprocessor, no build step (Propshaft serves it directly). CSS custom properties for all tokens — components reference variable names, never raw hex values.

### Font Loading

Google Fonts loaded via `<link>` in the application layout `<head>`:

```html
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Outfit:wght@400;500;600;700;900&family=Space+Grotesk:wght@400;500;600;700&family=DM+Mono:wght@300;400;500&display=swap" rel="stylesheet">
```

---

## Anti-Patterns

### Don't

- **Full-width rows** with info far-left and actions far-right — keep info and actions close together
- **Database IDs** shown to users — always resolve to meaningful names
- **Jargon** without plain-language explanation
- **Generic "pile of cards"** layouts — use intentional grouping and hierarchy
- **Decorative motifs in data-dense areas** — motifs are for breathing room, not clutter
- **Starburst or boomerang in Silo** — Silo gets atom markers, diamond dividers, and radar sweeps only
- **Hardcoded hex values** in components — always use CSS custom properties
- **Mixing font roles** — don't use Outfit for body text or DM Mono for headings

### Do

- **Compact action cards** — info + actions close together, no sprawl
- **Resolve IDs to names** — always show meaningful labels
- **DM Mono for technical metadata** — timestamps, status codes, counts
- **Left-border accent** for items needing attention
- **Color-coded bottom borders** for navigation categories
- **Atom marker** for all section headers in both themes
- **Semantic color variables** — `--color-success`, not `#2a7a4a`
- **Progressive disclosure** — inverted pyramid layout (headline → highlights → details)

---

## Theme Personality Guide

When building a new page, ask: "Is this the living room or the silo?"

### Living Room (Public)

- Warm cream background, generous whitespace
- Decorative motifs in hero/header areas (boomerangs, starbursts, orbital rings at low opacity)
- Terra cotta for section labels and CTAs
- Outfit headlines are prominent and warm
- Content reads like a newspaper — editorial voice, clear hierarchy
- Tone: "Come sit down, here's what happened at city hall"

### Silo (Admin)

- Cool concrete background, efficient density
- Minimal decoration — atom markers for section headers, radar sweep for dashboard only
- Deep teal dominates the chrome — nav bars, section headers, borders
- Amber for warnings and active states, terra cotta for destructive actions
- Data-forward — DM Mono metadata is prominent, tables are the primary layout
- Tone: "Here's the control panel, everything you need is within reach"
