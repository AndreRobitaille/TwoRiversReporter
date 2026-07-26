# test/assets/admin_stylesheet_test.rb
require "test_helper"
require "set"

class AdminStylesheetTest < ActiveSupport::TestCase
  STYLESHEET = Rails.root.join("app/assets/stylesheets/admin.css")

  UTILITIES = %w[
    m-0 mt-1 mt-3 mb-1 mb-3 mx-2 my-6 p-3 p-4 p-6
    gap-3 gap-6 space-y-2 space-y-3 space-y-6
    grid grid-cols-2 grow items-start justify-end align-middle
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
end
