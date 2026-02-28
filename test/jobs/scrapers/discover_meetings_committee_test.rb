require "test_helper"

class Scrapers::DiscoverMeetingsCommitteeTest < ActiveSupport::TestCase
  test "Committee.resolve finds by exact name" do
    committee = Committee.create!(name: "City Council")
    assert_equal committee, Committee.resolve("City Council")
  end

  test "Committee.resolve finds by alias" do
    committee = Committee.create!(name: "City Council")
    CommitteeAlias.create!(committee: committee, name: "City Council Meeting")
    assert_equal committee, Committee.resolve("City Council Meeting")
  end

  test "Committee.resolve returns nil for unrecognized body_name" do
    assert_nil Committee.resolve("Totally Unknown Board Meeting")
  end
end
