require "test_helper"

class CommitteeTest < ActiveSupport::TestCase
  test "valid committee saves" do
    committee = Committee.new(name: "City Council", description: "Legislative body")
    assert committee.save
    assert_equal "city-council", committee.slug
  end

  test "name is required" do
    committee = Committee.new(description: "No name")
    assert_not committee.valid?
    assert_includes committee.errors[:name], "can't be blank"
  end

  test "name must be unique" do
    Committee.create!(name: "City Council")
    duplicate = Committee.new(name: "City Council")
    assert_not duplicate.valid?
  end

  test "slug auto-generated from name" do
    committee = Committee.create!(name: "Plan Commission")
    assert_equal "plan-commission", committee.slug
  end

  test "committee_type validates inclusion" do
    committee = Committee.new(name: "Test", committee_type: "invalid")
    assert_not committee.valid?
    assert_includes committee.errors[:committee_type], "is not included in the list"
  end

  test "status validates inclusion" do
    committee = Committee.new(name: "Test", status: "invalid")
    assert_not committee.valid?
    assert_includes committee.errors[:status], "is not included in the list"
  end

  test "committee_type defaults to city" do
    committee = Committee.create!(name: "Test Board")
    assert_equal "city", committee.committee_type
  end

  test "status defaults to active" do
    committee = Committee.create!(name: "Test Board")
    assert_equal "active", committee.status
  end

  test "active scope returns active committees" do
    active = Committee.create!(name: "Active Board", status: "active")
    Committee.create!(name: "Dormant Board", status: "dormant")
    Committee.create!(name: "Dissolved Board", status: "dissolved")

    assert_includes Committee.active, active
    assert_equal 1, Committee.active.count
  end

  test "for_ai_context returns active and dormant with descriptions" do
    active = Committee.create!(name: "Active Board", description: "Does things")
    dormant = Committee.create!(name: "Dormant Board", status: "dormant", description: "Sleeping")
    Committee.create!(name: "Dissolved Board", status: "dissolved", description: "Gone")
    Committee.create!(name: "No Desc Board", status: "active", description: nil)

    results = Committee.for_ai_context
    assert_includes results, active
    assert_includes results, dormant
    assert_equal 2, results.count
  end

  test "resolve finds by name" do
    committee = Committee.create!(name: "City Council")
    assert_equal committee, Committee.resolve("City Council")
  end

  test "resolve finds by alias" do
    committee = Committee.create!(name: "Central Park West 365 Planning Committee")
    CommitteeAlias.create!(committee: committee, name: "Splash Pad and Ice Rink Planning Committee")
    assert_equal committee, Committee.resolve("Splash Pad and Ice Rink Planning Committee")
  end

  test "resolve returns nil for unknown name" do
    assert_nil Committee.resolve("Nonexistent Board")
  end

  test "resolve strips canceled suffix" do
    committee = Committee.create!(name: "City Council")
    CommitteeAlias.create!(committee: committee, name: "City Council Meeting")
    assert_equal committee, Committee.resolve("City Council Meeting - CANCELED")
  end

  test "resolve strips no quorum suffix" do
    committee = Committee.create!(name: "City Council")
    CommitteeAlias.create!(committee: committee, name: "City Council Meeting")
    assert_equal committee, Committee.resolve("City Council Meeting - CANCELED - NO QUORUM")
  end
end
