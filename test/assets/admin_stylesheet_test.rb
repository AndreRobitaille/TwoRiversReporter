# test/assets/admin_stylesheet_test.rb
require "test_helper"
require "set"

class AdminStylesheetTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/stylesheets/admin.css")

  UTILITIES = %w[
    m-0 mt-1 mt-3 mb-1 mb-3 mx-2 my-6 p-3 p-4 p-6
    gap-3 gap-6 space-y-2 space-y-3 space-y-4 space-y-6
    grid grid-cols-2 grow items-start items-end justify-end align-middle
    w-8 whitespace-nowrap cursor-pointer
    text-left text-lg text-md font-semibold font-mono italic
    border-l border-t border-gray-200 border-yellow-200 border-danger-light
    bg-white bg-slate-50 bg-yellow-50
    text-yellow-600 text-yellow-700 text-yellow-800
  ].freeze

  # Section 4 ("Utilities") is the transitional layer and is guaranteed to
  # stay last in the file (Tasks 9/10/11 only ever append into sections 1-3
  # above it), so "from the section header to end of file" is a stable
  # boundary.
  UTILITIES_SECTION_HEADER = /\/\*\s*=+\s*\n\s*4\.\s*Utilities.*?=+\s*\*\//m

  def css
    @css ||= STYLESHEET.read
  end

  # Extracts the actual class selectors defined in the utilities section of
  # admin.css, so drift can be caught in either direction: a class added to
  # the CSS without updating UTILITIES, or one removed from the CSS while
  # still listed.
  def defined_utility_classes
    header_match = css.match(UTILITIES_SECTION_HEADER)
    assert header_match, "could not find the '4. Utilities' section header in admin.css"

    section = css[header_match.end(0)..]
    section = section.gsub(/\/\*.*?\*\//m, "") # drop comments so prose mentions of ".foo" aren't parsed as selectors

    section.scan(/([^{}]+)\{[^{}]*\}/m).flatten.flat_map do |selector_list|
      selector_list.split(",").map do |selector|
        # Take only the leading class token, so combinators like
        # ".space-y-2 > * + *" yield "space-y-2", not the whole selector.
        selector.strip[/\A\.([a-zA-Z0-9_-]+)/, 1]
      end
    end.compact.to_set
  end

  test "defines every transitional utility the admin views already use" do
    missing = UTILITIES.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "the utilities section defines exactly the tracked set, no more, no fewer" do
    expected = UTILITIES.to_set
    actual = defined_utility_classes
    missing_from_css = (expected - actual).to_a.sort
    extra_in_css = (actual - expected).to_a.sort

    assert_equal expected, actual,
      "utilities drifted — tracked in UTILITIES but not defined in admin.css: " \
      "#{missing_from_css.join(', ').presence || 'none'}; " \
      "defined in admin.css but not tracked in UTILITIES: " \
      "#{extra_in_css.join(', ').presence || 'none'}"
  end

  test "hardcodes no hex colours" do
    offenders = css.scan(/#[0-9a-fA-F]{3,8}\b/)
    assert_empty offenders,
      "admin.css must use design tokens, not literal colours: #{offenders.uniq.join(', ')}"
  end

  MISTAKES = {
    "atom-marker"          => 'render "shared/atom_marker", theme: "silo"',
    "section-header-label" => "section-header__label",
    "section-header-line"  => "section-header__line"
  }.freeze

  # `table` is deliberately absent: the data-table component (Task 10) owns the
  # bare <table> element. Asserting it here would leave the suite red for three
  # tasks. Do not add it.
  PAGE_CONTAINERS = %w[
    table-responsive table-desc timestamp breadcrumb form-help
    flash-messages page-header-row badge--muted prose--sm
    topic-board-header transcript-imports-page transcript-imports-table-wrap
    transcript-imports-step-logs prompt-run-message generated-image-panel__block
  ].freeze

  test "the three motif and section-header mistakes are gone from every admin view" do
    views = Dir[Rails.root.join("app/views/admin/**/*.erb")]

    MISTAKES.each do |wrong, right|
      offenders = views.select do |path|
        File.read(path).match?(/\b#{Regexp.escape(wrong)}\b/)
      end
      assert_empty offenders.map { |p| p.sub("#{Rails.root}/", "") },
        "`#{wrong}` is undefined — use #{right} instead"
    end
  end

  test "defines every remaining page and component container" do
    missing = PAGE_CONTAINERS.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  SHELL = %w[
    adm-shell adm-sidebar adm-sidebar__brand adm-sidebar__group adm-sidebar__link
    adm-sidebar__link--current adm-sidebar__foot adm-main adm-container
    adm-drawer-toggle adm-scrim adm-launcher adm-launcher__group adm-launcher__title
    adm-launcher__list adm-launcher__item adm-launcher__link adm-launcher__desc
    adm-page-header adm-page-header__eyebrow adm-page-header__title adm-page-header__meta
  ].freeze

  test "defines the shell, sidebar, launcher, and page header" do
    missing = SHELL.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "collapses the sidebar to a drawer on small screens" do
    assert_match(/@media\s*\(max-width:\s*900px\)/, css)
  end

  # `.theme-silo h1, h2, h3, h4 { ... }` is a class+type selector — specificity
  # (0,1,1). Any admin component class rendered directly on a heading element
  # must be scoped as `.theme-silo .the-class` (0,2,0) to reliably win that
  # tie, regardless of source order. A bare `.the-class` (0,1,0) loses no
  # matter where it's written in the file. This test is data-driven from the
  # actual view markup (not a hardcoded pair of classes) so it keeps working
  # as Tasks 10-11 add headings to new components.
  def adm_classes_on_headings
    Dir[Rails.root.join("app/views/admin/**/*.erb")].flat_map do |path|
      File.read(path).scan(/<h[1-4][^>]*\bclass="([^"]*)"/).flatten
    end.flat_map { |class_list| class_list.split(/\s+/) }
       .select { |cls| cls.start_with?("adm-") }
       .uniq
  end

  test "adm-* classes rendered on headings are .theme-silo-scoped to beat the element-qualified heading rule" do
    heading_classes = adm_classes_on_headings
    assert_not_empty heading_classes,
      "expected at least one .adm-* class to be rendered on a heading element " \
      "in app/views/admin — if this is legitimately zero now, this test has nothing to check"

    unscoped = heading_classes.reject do |cls|
      css.match?(/\.theme-silo\s+\.#{Regexp.escape(cls)}(?![a-zA-Z0-9_-])/)
    end

    assert_empty unscoped,
      "these classes render on h1-h4 elements but their admin.css rule is not " \
      "`.theme-silo .the-class`-scoped, so `.theme-silo h1..h4` (0,1,1) silently " \
      "wins the properties both set: #{unscoped.join(', ')}"
  end

  DATA_COMPONENTS = %w[
    adm-table adm-table__sort adm-table__row--ok adm-table__row--warn adm-table__row--danger
    adm-chip adm-chip--ok adm-chip--warn adm-chip--danger adm-chip--info adm-chip--neutral
    adm-pagination adm-empty table
  ].freeze

  test "defines the data table, chips, pagination, and empty state" do
    missing = DATA_COMPONENTS.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "table metadata cells use the data typeface" do
    assert_match(/--font-data/, css)
  end

  CHROME_COMPONENTS = %w[
    adm-toolbar adm-seg adm-seg__option adm-seg__option--on
    adm-panel adm-panel__label adm-detail adm-detail__main adm-detail__rail
  ].freeze

  test "defines the toolbar, segmented control, panel, and detail layout" do
    missing = CHROME_COMPONENTS.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "shared component names are overridden scoped to the admin theme only" do
    %w[card btn badge form-input flash modal].each do |shared|
      assert_match(/\.theme-silo\s+\.#{Regexp.escape(shared)}(?![a-zA-Z0-9_-])/, css,
        ".#{shared} must be overridden as `.theme-silo .#{shared}` so the public site is untouched")
    end
  end

  # --- Task 11 fix-round-1: guard against the root cause, not just the three
  # confirmed instances (.btn--secondary's colour, .card--ai-answer's
  # border-left, every tinted .badge--* variant's border-color). Every one of
  # those was the SAME mechanism: a scoped BASE component rule this file adds
  # (e.g. `.theme-silo .badge`) touches a colour-carrying property that a
  # component MODIFIER in application.css (e.g. `.badge--primary`, whether
  # written bare or already `.theme-silo`-scoped there) also sets, and the
  # base rule wins — by higher specificity when the modifier is bare and
  # unscoped, or by admin.css loading after application.css when the
  # modifier is already `.theme-silo`-scoped there (the exact badge case:
  # both rules are (0,2,0), a tie, and file load order breaks it). Either
  # way the modifier's distinguishing colour silently flattens to the base's
  # neutral one. This test is data-driven from the stylesheets themselves so
  # it catches instance nine without another manual audit.
  #
  # Deliberately scoped to COLOR_PROPERTIES, not "any overlapping property":
  # padding/font-size/border-radius/letter-spacing/text-transform are
  # INTENTIONALLY unified across every admin badge/button/card by the base
  # rule — that uniform density retrofit is the whole point of this file,
  # not a bug. Flagging those would demand reassertion rules that just
  # restate the base's own values back to itself. What actually broke was
  # distinguishing colour, not shared sizing/shape.
  #
  # BASES is hardcoded, matching this file's existing style (CHROME_COMPONENTS,
  # SHELL, DATA_COMPONENTS, etc. above are all hardcoded too) — extend it
  # when a future task scopes another shared name.
  BASES = %w[btn card badge flash form-input form-select form-textarea modal].freeze

  COLOR_PROPERTIES = %w[
    color background background-color
    border border-color
    border-top border-top-color border-right border-right-color
    border-bottom border-bottom-color border-left border-left-color
    outline outline-color
  ].to_set.freeze

  # `border`/`background`/per-side border shorthands set their -color
  # longhand as a side effect, which is exactly how `.theme-silo .card`'s
  # `border: var(--adm-hairline)` ends up clobbering `.card--ai-answer`'s
  # `border-left` — so a shorthand must be treated as also touching its
  # implied longhands, or the overlap this test looks for would never be
  # detected in the one property form that actually caused every confirmed
  # instance.
  SHORTHAND_EXPANSION = {
    "border" => %w[border-color border-top-color border-right-color border-bottom-color border-left-color],
    "background" => %w[background-color],
    "border-top" => %w[border-top-color],
    "border-right" => %w[border-right-color],
    "border-bottom" => %w[border-bottom-color],
    "border-left" => %w[border-left-color],
    "outline" => %w[outline-color]
  }.freeze

  # Parses "selector-list { declarations }" blocks via the same non-nested-
  # brace scan `defined_utility_classes` above already relies on. Applied to
  # a whole stylesheet (not just one section) it still works for our
  # purposes: an `@media (...) {` wrapper never itself resolves to a clean
  # "selectors { decls }" match (its own body starts with another `{` before
  # a matching `}` is reached), so the scan simply fails there and continues
  # from the next position — which still finds the flat, one-level-nested
  # rules inside the media block correctly. We only read flat modifier/base
  # rules here, none of which happen to depend on which media query (if any)
  # wraps them.
  def parse_flat_rules(text)
    text = text.gsub(%r{/\*.*?\*/}m, "")
    text.scan(/([^{}]+)\{([^{}]*)\}/m).map do |selectors, body|
      props = body.split(";").filter_map { |decl| decl.split(":", 2).first&.strip }.reject(&:empty?)
      { selectors: selectors.split(",").map(&:strip), properties: props.to_set }
    end
  end

  def expand_properties(props)
    props.flat_map { |p| [ p ] + SHORTHAND_EXPANSION.fetch(p, []) }.to_set
  end

  # Collects every VARIANT of `base` that application.css defines — a flat
  # modifier (`.base--x`), a pseudo-class on the base itself (`.base:hover`),
  # or a pseudo-class on a modifier (`.base--x:hover`) — whether written bare
  # or already `.theme-silo`-scoped there (the pre-revamp badge case).
  # `(--[a-zA-Z0-9_-]+)?` and `(:[a-zA-Z-]+)?` are both optional so a single
  # pattern covers all three shapes; the fully-bare "no modifier, no pseudo"
  # match (the base's own rest-state rule in application.css, e.g. plain
  # `.card { ... }`) is discarded — that's the "shared name is overridden at
  # all" question the "shared component names" test above already owns, not
  # this one. Keyed by `[modifier_suffix, pseudo_suffix]` (either or both may
  # be nil); properties from bare and already-scoped forms are unioned.
  def application_css_variants_of(base, app_rules)
    pattern = /\A(?:\.theme-silo\s+)?\.#{Regexp.escape(base)}(--[a-zA-Z0-9_-]+)?(:[a-zA-Z-]+)?\z/
    found = Hash.new { |h, k| h[k] = Set.new }
    app_rules.each do |rule|
      rule[:selectors].each do |sel|
        match = sel.match(pattern)
        next unless match
        modifier_suffix, pseudo_suffix = match[1], match[2]
        next if modifier_suffix.nil? && pseudo_suffix.nil?
        found[[ modifier_suffix, pseudo_suffix ]] |= expand_properties(rule[:properties])
      end
    end
    found
  end

  # The colour-carrying properties of `.theme-silo .base#{pseudo_suffix}` in
  # ADMIN.CSS, if such a rule exists (e.g. `.theme-silo .btn:hover`) — a
  # second, independent way a variant can get clobbered: a base's own pseudo
  # rule (one class-equivalent more specific than a bare `.base--x:pseudo`
  # modifier rule) can beat that modifier's pseudo rule outright, not just
  # tie with it. This is exactly the mechanism behind three of fix-round-1's
  # `.btn--*:hover` fixes (`.theme-silo .btn:hover` at (0,3,0) beat
  # `.btn--danger:hover` at (0,2,0) outright).
  def admin_css_base_pseudo_props(base, pseudo_suffix, admin_rules)
    return Set.new unless pseudo_suffix
    rule = admin_rules.find { |r| r[:selectors].include?(".theme-silo .#{base}#{pseudo_suffix}") }
    rule ? expand_properties(rule[:properties]) : Set.new
  end

  # Task 11 fix-round-2: `.card--clickable` has zero usages anywhere in
  # app/views (confirmed via grep across the whole app, not just admin), so
  # `.theme-silo .card--clickable:hover` would be dead code today — the
  # coordinator asked this be *noted*, not fixed, unlike `.card--highlighted`
  # in round 1 (also then-unused, but fixed anyway since it cost nothing and
  # a real element could pick up the class at any time). Listed here, not
  # silently ignored, so if `.card--clickable` is ever wired up without
  # anyone re-running this sweep, this exception is the one place that has
  # to be revisited — search this constant, not the whole file, when that
  # happens. See task-11-report.md, "Fix round 2", for the full reasoning.
  KNOWN_DEFERRED_CLOBBERS = Set[".theme-silo .card--clickable:hover"].freeze

  test "scoped base components do not clobber a variant's colour-carrying properties without a reassertion" do
    admin_rules = parse_flat_rules(css)
    app_rules = parse_flat_rules(Rails.root.join("app/assets/stylesheets/application.css").read)

    # Exact selector-string membership, not a loose substring regex: a loose
    # `/\.theme-silo\s+\.btn--secondary(?![a-zA-Z0-9_-])/` also matches
    # `.theme-silo .btn--secondary:hover { ... }` (the char after
    # `btn--secondary` is `:`, which isn't in the disallowed set either), so
    # a hover-only reassertion would silently satisfy the check for the
    # non-hover rest-state rule this test actually needs to exist. Proven by
    # temporarily deleting just `.theme-silo .btn--secondary { color: ... }`
    # while leaving `.theme-silo .btn--secondary:hover` in place — a loose
    # regex kept passing; exact-selector membership correctly failed.
    admin_selectors = admin_rules.flat_map { |r| r[:selectors] }.to_set

    missing = []

    BASES.each do |base|
      base_rule = admin_rules.find { |r| r[:selectors].include?(".theme-silo .#{base}") }
      next unless base_rule # this BASE isn't scoped (yet) here — nothing to guard

      base_color_props = expand_properties(base_rule[:properties]) & COLOR_PROPERTIES

      application_css_variants_of(base, app_rules).each do |(modifier_suffix, pseudo_suffix), variant_props|
        variant_color_props = variant_props & COLOR_PROPERTIES
        next if variant_color_props.empty?

        # Either the base's own rest-state rule (ties on specificity, wins
        # because admin.css loads after application.css) or the base's own
        # same-pseudo rule (wins outright on specificity) can be the thing
        # that clobbers this variant — check both, not just the rest-state
        # one, or the three `.btn--*:hover` instances from round 1 would be
        # invisible to this test.
        competing_props = base_color_props | admin_css_base_pseudo_props(base, pseudo_suffix, admin_rules)
        next if (competing_props & variant_color_props).empty?

        required_selector = ".theme-silo .#{base}#{modifier_suffix}#{pseudo_suffix}"
        next if KNOWN_DEFERRED_CLOBBERS.include?(required_selector)
        missing << required_selector unless admin_selectors.include?(required_selector)
      end
    end

    assert_empty missing.uniq.sort,
      "these variants (modifiers, and/or pseudo-classes on the base or a " \
      "modifier) share a colour-carrying property with their scoped base " \
      "rule but admin.css has no `.theme-silo` reassertion for them, so the " \
      "base rule's specificity (or, when application.css already scoped the " \
      "variant too, admin.css loading after application.css) silently " \
      "flattens their colour to the base's: #{missing.uniq.sort.join(', ')}"
  end
end
