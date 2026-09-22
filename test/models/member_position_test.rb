require "test_helper"

class MemberPositionTest < ActiveSupport::TestCase
  setup do
    @member = Member.create!(name: "Office Holder")
    @attributes = {
      member: @member,
      kind: "city_manager",
      title: "City Manager",
      source: "official_website",
      source_url: "https://example.com/manager",
      verified_at: Time.current
    }
  end

  test "validates kind and source" do
    assert MemberPosition.new(@attributes).valid?
    assert_not MemberPosition.new(@attributes.merge(kind: "staff")).valid?
    assert_not MemberPosition.new(@attributes.merge(source: "minutes")).valid?
  end

  test "allows only one current position of each kind per member" do
    MemberPosition.create!(@attributes)

    duplicate = MemberPosition.new(@attributes)
    assert_not duplicate.valid?
  end

  test "allows historical terms of the same kind" do
    MemberPosition.create!(@attributes.merge(ended_on: Date.yesterday))

    assert MemberPosition.new(@attributes).valid?
  end
end
