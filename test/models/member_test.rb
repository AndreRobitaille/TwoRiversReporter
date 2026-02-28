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

  # --- resolve ---

  test "resolve finds existing member by exact normalized name" do
    member = Member.create!(name: "Doug Brandt")
    assert_equal member, Member.resolve("Doug Brandt")
  end

  test "resolve finds member by alias" do
    member = Member.create!(name: "Doug Brandt")
    MemberAlias.create!(member: member, name: "Douglas Brandt")
    assert_equal member, Member.resolve("Douglas Brandt")
  end

  test "resolve auto-aliases last-name-only when one match" do
    member = Member.create!(name: "Doug Brandt")
    resolved = Member.resolve("Brandt")

    assert_equal member, resolved
    assert MemberAlias.exists?(member: member, name: "Brandt")
  end

  test "resolve does not auto-alias last-name-only when multiple matches" do
    Member.create!(name: "Doug Brandt")
    Member.create!(name: "Susie Brandt")

    resolved = Member.resolve("Brandt")

    assert_equal "Brandt", resolved.name
    assert_not_equal "Doug Brandt", resolved.name
    assert_not MemberAlias.exists?(name: "Brandt")
  end

  test "resolve creates new member when no match" do
    assert_difference "Member.count", 1 do
      member = Member.resolve("Jane Doe")
      assert_equal "Jane Doe", member.name
    end
  end

  test "resolve handles Council Rep prefix and via telephone suffix together" do
    member = Member.create!(name: "John Smith")
    assert_equal member, Member.resolve("Council Rep John Smith (via telephone)")
  end

  test "resolve returns existing member without creating duplicates" do
    Member.create!(name: "Doug Brandt")

    assert_no_difference "Member.count" do
      Member.resolve("Doug Brandt")
    end
  end

  test "resolve is idempotent for auto-aliasing" do
    member = Member.create!(name: "Doug Brandt")

    first_resolve = Member.resolve("Brandt")
    assert_equal member, first_resolve

    assert_no_difference "MemberAlias.count" do
      second_resolve = Member.resolve("Brandt")
      assert_equal member, second_resolve
    end
  end

  test "resolve returns nil for blank input" do
    assert_nil Member.resolve("")
    assert_nil Member.resolve("   ")
  end

  test "resolve returns nil for nil input" do
    assert_nil Member.resolve(nil)
  end
end
