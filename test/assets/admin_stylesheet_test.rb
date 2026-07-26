# test/assets/admin_stylesheet_test.rb
require "test_helper"
require "set"

class AdminStylesheetTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/stylesheets/admin.css")

  UTILITIES = %w[
    m-0 mt-1 mt-3 mb-1 mb-3 mx-2 mr-2 my-6 p-3 p-4 p-6 px-2 py-1
    gap-3 gap-6 space-y-2 space-y-3 space-y-4 space-y-6
    grid grid-cols-2 grow inline-flex items-start items-end justify-end align-middle
    w-8 w-16 whitespace-nowrap cursor-pointer
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
end
