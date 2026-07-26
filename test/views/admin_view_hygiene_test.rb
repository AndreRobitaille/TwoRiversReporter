# test/views/admin_view_hygiene_test.rb
require "test_helper"

# Guards against the two failure modes found in the July 2026 admin audit:
# 32 of 60 views referencing class names no stylesheet defined, and ~50
# inline style attributes standing in for components that did not exist.
class AdminViewHygieneTest < ActiveSupport::TestCase
  STYLESHEETS = Rails.root.glob("app/assets/stylesheets/*.css")
  VIEWS = Rails.root.glob("app/views/admin/**/*.erb")

  # Class names built by ERB interpolation can't be checked statically.
  # Only literal, fully-formed class attributes are considered.
  LITERAL_CLASS_ATTR = /class="([^"<%]*)"/

  def defined_classes
    @defined_classes ||= STYLESHEETS.flat_map { |f| f.read.scan(/\.([a-zA-Z_][a-zA-Z0-9_-]*)/) }.flatten.to_set
  end

  def classes_used_in(path)
    path.read.scan(LITERAL_CLASS_ATTR).flatten
        .flat_map(&:split)
        .grep(/\A[a-zA-Z][a-zA-Z0-9_-]*\z/)
  end

  test "every class an admin view names is defined by some stylesheet" do
    undefined = Hash.new { |h, k| h[k] = [] }

    VIEWS.each do |path|
      (classes_used_in(path).uniq - defined_classes.to_a).each do |klass|
        undefined[klass] << path.relative_path_from(Rails.root).to_s
      end
    end

    assert_empty undefined,
      "these classes are used but defined nowhere:\n" +
      undefined.map { |k, v| "  .#{k} — #{v.join(', ')}" }.join("\n")
  end
end
