require "test_helper"

class MemberAliasTest < ActiveSupport::TestCase
  setup do
    @member = Member.create!(name: "John Smith")
  end

  test "valid alias saves" do
    alias_record = MemberAlias.new(member: @member, name: "J. Smith")
    assert alias_record.save
  end

  test "name is required" do
    alias_record = MemberAlias.new(member: @member, name: "")
    assert_not alias_record.valid?
  end

  test "name must be unique" do
    MemberAlias.create!(member: @member, name: "Johnny Smith")
    duplicate = MemberAlias.new(member: @member, name: "Johnny Smith")
    assert_not duplicate.valid?
  end

  test "name is stripped and squished" do
    alias_record = MemberAlias.create!(member: @member, name: "  Extra   Spaces  ")
    assert_equal "Extra Spaces", alias_record.name
  end

  test "member association required" do
    alias_record = MemberAlias.new(name: "Orphan Alias")
    assert_not alias_record.valid?
  end
end
