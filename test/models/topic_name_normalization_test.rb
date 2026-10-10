require "test_helper"

class TopicNameNormalizationTest < ActiveSupport::TestCase
  test "folds hyphens, slashes, and unicode dashes into spaces" do
    assert_equal "right of way", Topic.normalize_name("right-of-way")
    assert_equal "right of way", Topic.normalize_name("right/of/way")
    assert_equal "right of way", Topic.normalize_name("RIGHT-OF-WAY")
    assert_equal "right of way", Topic.normalize_name("right\u2013of\u2013way")
    assert_equal "right of way", Topic.normalize_name("right\u2014of\u2014way")
    assert_equal "right of way", Topic.normalize_name("right\u2212of\u2212way")
    assert_equal "right of way", Topic.normalize_name("right\u2011of\u2011way")
  end

  test "slash names become the spaced forms and do not insert and" do
    leaks = Topic.normalize_name("internal leaks/meter technology")
    signals = Topic.normalize_name("traffic signals/assessment inspection")

    assert_equal "internal leaks meter technology", leaks
    assert_equal "traffic signals assessment inspection", signals
    refute_includes leaks, "and"
    refute_includes signals, "and"
    assert_equal "parks rec", Topic.normalize_name("parks & rec")
  end

  test "still strips apostrophes and other punctuation after the space fold" do
    assert_equal "councils budget", Topic.normalize_name("Council's Budget")
    assert_equal "door to door solicitation permits", Topic.normalize_name("Door-to-Door Solicitation Permits!")
  end

  test "alias and blocklist use the shared normalizer" do
    topic = Topic.create!(name: "harbor dredging", status: "approved")
    topic_alias = TopicAlias.create!(topic: topic, name: "Right/Of/Way Permits")
    blocked = TopicBlocklist.create!(name: "Parks & Rec")

    assert_equal "right of way permits", topic_alias.name
    assert_equal "parks rec", blocked.name
    refute_includes topic_alias.name, "and"
    refute_includes blocked.name, "and"
  end

  test "finds a topic by folded name or by a glued alias" do
    topic = Topic.create!(name: "right of way", status: "approved")
    TopicAlias.create!(topic: topic, name: "rightofway")
    proposed = Topic.create!(name: "self storage development", status: "proposed")
    TopicAlias.create!(topic: proposed, name: "selfstoragedevelopment")

    assert_equal topic, Topic.find_by_name_or_alias("right-of-way")
    assert_equal topic, Topic.find_by_name_or_alias("right/of/way")
    assert_equal topic, Topic.find_by_name_or_alias("rightofway")
    assert_nil Topic.find_by_name_or_alias("rightofway", Topic.approved.where.not(id: topic.id))
    assert_nil Topic.find_by_name_or_alias("self-storage development", Topic.approved)
    assert_equal proposed, Topic.find_by_name_or_alias("selfstoragedevelopment")
  end

  test "exact topic name outranks an alias with the same string" do
    canonical = Topic.create!(name: "harbor project", status: "approved")
    other = Topic.create!(name: "harbor dredging", status: "approved")
    TopicAlias.create!(topic: other, name: "harbor project")

    assert_equal canonical, Topic.find_by_name_or_alias("Harbor Project")
  end
end
