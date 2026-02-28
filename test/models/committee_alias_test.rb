require "test_helper"

class CommitteeAliasTest < ActiveSupport::TestCase
  setup do
    @committee = Committee.create!(name: "Central Park West 365 Planning Committee")
  end

  test "valid alias saves" do
    alias_record = CommitteeAlias.new(committee: @committee, name: "Splash Pad Committee")
    assert alias_record.save
  end

  test "name is required" do
    alias_record = CommitteeAlias.new(committee: @committee, name: "")
    assert_not alias_record.valid?
  end

  test "name must be unique" do
    CommitteeAlias.create!(committee: @committee, name: "Old Name")
    duplicate = CommitteeAlias.new(committee: @committee, name: "Old Name")
    assert_not duplicate.valid?
  end

  test "name is stripped and squished" do
    alias_record = CommitteeAlias.create!(committee: @committee, name: "  Extra   Spaces  ")
    assert_equal "Extra Spaces", alias_record.name
  end

  test "committee association required" do
    alias_record = CommitteeAlias.new(name: "Orphan Alias")
    assert_not alias_record.valid?
  end
end
