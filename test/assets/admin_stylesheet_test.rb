# test/assets/admin_stylesheet_test.rb
require "test_helper"

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

  def css
    @css ||= STYLESHEET.read
  end

  test "defines every transitional utility the admin views already use" do
    missing = UTILITIES.reject { |c| css.match?(/\.#{Regexp.escape(c)}(?![a-zA-Z0-9_-])/) }
    assert_empty missing, "admin.css does not define: #{missing.join(', ')}"
  end

  test "there are exactly 41 utilities, so the list cannot quietly grow" do
    assert_equal 41, UTILITIES.length
  end

  test "hardcodes no hex colours" do
    offenders = css.scan(/#[0-9a-fA-F]{3,8}\b/)
    assert_empty offenders,
      "admin.css must use design tokens, not literal colours: #{offenders.uniq.join(', ')}"
  end
end
