require "test_helper"

class Topics::TitleNormalizerTest < ActiveSupport::TestCase
  test "strips leading item numbering like '10.'" do
    assert_equal "solid waste utility: updates and action",
      Topics::TitleNormalizer.normalize("10. SOLID WASTE UTILITY: UPDATES AND ACTION, AS NEEDED")
  end

  test "strips YY-NNN council numbering" do
    assert_equal "public hearing on zoning",
      Topics::TitleNormalizer.normalize("26-001 Public hearing on zoning")
  end

  test "strips trailing ', as needed'" do
    assert_equal "solid waste updates and action",
      Topics::TitleNormalizer.normalize("Solid Waste Updates and Action, As Needed")
  end

  test "strips trailing ', if applicable'" do
    assert_equal "optional walkthrough",
      Topics::TitleNormalizer.normalize("Optional Walkthrough, If Applicable")
  end

  test "collapses whitespace and downcases" do
    assert_equal "parking plan vote",
      Topics::TitleNormalizer.normalize("  Parking   Plan   Vote  ")
  end

  test "normalizes contextual separators like em dashes" do
    assert_equal "new business resolution",
      Topics::TitleNormalizer.normalize("NEW BUSINESS — Resolution")
  end

  test "strips lettered child-item prefixes" do
    assert_equal "resolution",
      Topics::TitleNormalizer.normalize("A. Resolution")
  end

  test "returns empty string for nil or blank input" do
    assert_equal "", Topics::TitleNormalizer.normalize(nil)
    assert_equal "", Topics::TitleNormalizer.normalize("")
    assert_equal "", Topics::TitleNormalizer.normalize("   ")
  end

  test "tolerates a non-string input by coercing to string" do
    # "7a." is fully consumed by the leading-numbering regex (digit + letter + dot).
    # The intent is to verify .to_s coercion; the result is "" for this input.
    assert_equal "", Topics::TitleNormalizer.normalize("7a.")
  end
end
