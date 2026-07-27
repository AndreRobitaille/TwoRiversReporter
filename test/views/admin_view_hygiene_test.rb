# test/views/admin_view_hygiene_test.rb
require "test_helper"

# Guards against the two failure modes found in the July 2026 admin audit:
# admin markup referencing class names no stylesheet defined, and inline style
# attributes standing in for components that did not exist.
class AdminViewHygieneTest < ActiveSupport::TestCase
  # Mirrors the admin layout's stylesheet_link_tag calls
  # (app/views/layouts/admin.html.erb) — update this list if that layout's
  # stylesheets change. home.css and about.css are deliberately excluded:
  # the admin layout never loads them, so a class defined only there would
  # look "defined" to this guard while being unstyled on every admin page —
  # the exact failure this guard exists to catch, through a different door.
  STYLESHEETS = %w[application admin].map { |name| Rails.root.join("app/assets/stylesheets/#{name}.css") }
  VIEWS = Rails.root.glob("app/views/admin/**/*.erb")
  MARKUP_SOURCES = VIEWS + Rails.root.glob("app/helpers/admin/**/*.rb")

  # Class names built by ERB interpolation (`<%= %>`) or Ruby string
  # interpolation (`#{}`) can't be checked statically. Only literal,
  # fully-formed class values are considered: HTML attributes, Rails helper
  # options, and escaped HTML inside Ruby helper strings.
  LITERAL_CLASS_PATTERNS = [
    /class="([^"]*)"/,
    /class:\s*"([^"]*)"/,
    /class=\\"([^"]*)\\"/
  ].freeze

  def defined_classes
    @defined_classes ||= STYLESHEETS.flat_map { |f| f.read.scan(/\.([a-zA-Z_][a-zA-Z0-9_-]*)/) }.flatten.to_set
  end

  def classes_used_in(path)
    text = path.read
    LITERAL_CLASS_PATTERNS
      .flat_map { |pattern| text.scan(pattern).flatten }
      .reject { |value| value.include?("<%") || value.include?('#{') }
      .flat_map(&:split)
      .grep(/\A[a-zA-Z][a-zA-Z0-9_-]*\z/)
  end

  test "every class admin views and helpers name is defined by some stylesheet" do
    undefined = Hash.new { |h, k| h[k] = [] }

    MARKUP_SOURCES.each do |path|
      (classes_used_in(path).uniq - defined_classes.to_a).each do |klass|
        undefined[klass] << path.relative_path_from(Rails.root).to_s
      end
    end

    assert_empty undefined,
      "these classes are used but defined nowhere:\n" +
      undefined.map { |k, v| "  .#{k} — #{v.join(', ')}" }.join("\n")
  end

  # Literal HTML attribute form (`style="..."`) and the Rails helper hash
  # form (`style: "..."`, as in `form.label ..., style: "margin-bottom: 0;"`
  # or `form: { style: "display:inline" }`) both render an inline `style="..."`
  # attribute at runtime — this is the exact blind spot LITERAL_CLASS_PATTERNS
  # already closed for `class` (Task 8: `class="..."` vs `class: "..."`), and
  # Task 16 fix-round-1 found the same gap still open for `style`. Excludes
  # anything containing `<%` or `#{` — an interpolated style value can't be
  # checked statically, same rule `classes_used_in` already applies.
  LITERAL_STYLE_PATTERNS = [
    /style="([^"]*)"/,
    /style:\s*"([^"]*)"/
  ].freeze

  def inline_style_count(path)
    text = path.read
    LITERAL_STYLE_PATTERNS
      .flat_map { |pattern| text.scan(pattern).flatten }
      .reject { |value| value.include?("<%") || value.include?('#{') }
      .length
  end

  test "no admin view uses an inline style attribute" do
    offenders = VIEWS.filter_map do |path|
      count = inline_style_count(path)
      "#{path.relative_path_from(Rails.root)} (#{count})" if count.positive?
    end

    assert_empty offenders,
      "inline styles mean a component is missing — grow the component instead:\n  " +
      offenders.join("\n  ")
  end

  test "no admin partial is orphaned" do
    sources = Rails.root.glob("app/{views,controllers}/**/*.{erb,rb}")
    orphans = []

    Rails.root.glob("app/views/admin/**/_*.erb").each do |partial|
      name = partial.basename.to_s.sub(/\A_/, "").sub(/\.html\.erb\z/, "")
      dir  = partial.dirname.relative_path_from(Rails.root.join("app/views")).to_s
      pattern = /render[( ][^\n]*["'](?:#{Regexp.escape(dir)}\/)?#{Regexp.escape(name)}["']|partial:\s*["'](?:#{Regexp.escape(dir)}\/)?#{Regexp.escape(name)}["']/

      referenced = sources.any? { |s| s != partial && s.read.match?(pattern) }
      orphans << partial.relative_path_from(Rails.root).to_s unless referenced
    end

    assert_empty orphans,
      "these partials are rendered by nothing — delete them or wire them up:\n  #{orphans.join("\n  ")}"
  end
end
