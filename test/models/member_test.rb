require "test_helper"

class MemberTest < ActiveSupport::TestCase
  # --- Title prefix stripping ---

  test "normalize_name strips Councilmember prefix" do
    assert_equal "John Smith", Member.normalize_name("Councilmember John Smith")
  end

  test "normalize_name strips Council Rep prefix" do
    assert_equal "Jane Doe", Member.normalize_name("Council Rep Jane Doe")
  end

  test "normalize_name strips Council Representative prefix" do
    assert_equal "Jane Doe", Member.normalize_name("Council Representative Jane Doe")
  end

  test "normalize_name strips Alderman prefix" do
    assert_equal "Bob Jones", Member.normalize_name("Alderman Bob Jones")
  end

  test "normalize_name strips Alderperson prefix" do
    assert_equal "Pat Lee", Member.normalize_name("Alderperson Pat Lee")
  end

  test "normalize_name strips Commissioner prefix" do
    assert_equal "Mary Clark", Member.normalize_name("Commissioner Mary Clark")
  end

  test "normalize_name strips Manager prefix" do
    assert_equal "Greg Hall", Member.normalize_name("Manager Greg Hall")
  end

  test "normalize_name strips Clerk prefix" do
    assert_equal "Sue White", Member.normalize_name("Clerk Sue White")
  end

  test "normalize_name strips Mr. prefix" do
    assert_equal "Tim Brown", Member.normalize_name("Mr. Tim Brown")
  end

  test "normalize_name strips Ms. prefix" do
    assert_equal "Lisa Green", Member.normalize_name("Ms. Lisa Green")
  end

  test "normalize_name strips Mrs. prefix" do
    assert_equal "Ann Black", Member.normalize_name("Mrs. Ann Black")
  end

  # --- Suffix stripping ---

  test "normalize_name strips (via telephone) suffix" do
    assert_equal "John Smith", Member.normalize_name("John Smith (via telephone)")
  end

  test "normalize_name strips (via phone) suffix" do
    assert_equal "John Smith", Member.normalize_name("John Smith (via phone)")
  end

  test "normalize_name strips (via Zoom) suffix" do
    assert_equal "John Smith", Member.normalize_name("John Smith (via Zoom)")
  end

  test "normalize_name strips (absent) suffix" do
    assert_equal "John Smith", Member.normalize_name("John Smith (absent)")
  end

  test "normalize_name strips (excused) suffix" do
    assert_equal "John Smith", Member.normalize_name("John Smith (excused)")
  end

  # --- Combined prefix + suffix ---

  test "normalize_name strips both prefix and suffix" do
    assert_equal "John Smith", Member.normalize_name("Councilmember John Smith (via Zoom)")
  end

  test "normalize_name strips Council Rep prefix with suffix" do
    assert_equal "Jane Doe", Member.normalize_name("Council Rep Jane Doe (via telephone)")
  end

  # --- Passthrough and edge cases ---

  test "normalize_name passes through normal names unchanged" do
    assert_equal "John Smith", Member.normalize_name("John Smith")
  end

  test "normalize_name squishes internal whitespace" do
    assert_equal "John Smith", Member.normalize_name("  John   Smith  ")
  end

  test "normalize_name handles nil input" do
    assert_equal "", Member.normalize_name(nil)
  end

  test "normalize_name handles empty string" do
    assert_equal "", Member.normalize_name("")
  end

  test "normalize_name is case-insensitive for prefixes" do
    assert_equal "John Smith", Member.normalize_name("COUNCILMEMBER John Smith")
  end

  test "normalize_name is case-insensitive for suffixes" do
    assert_equal "John Smith", Member.normalize_name("John Smith (VIA ZOOM)")
  end
end
