require "test_helper"
require Rails.root.join("db/migrate/20261005160000_space_fold_glued_topic_names")

class SpaceFoldGluedTopicNamesMigrationTest < ActiveSupport::TestCase
  setup do
    @migration = SpaceFoldGluedTopicNames.new
  end

  test "renames glued topics and keeps the glued string as an alias" do
    topics = SpaceFoldGluedTopicNames::RENAMES.keys.index_with do |glued|
      Topic.create!(name: glued, status: "approved")
    end

    @migration.up

    SpaceFoldGluedTopicNames::RENAMES.each do |glued, spaced|
      topic = topics.fetch(glued).reload
      assert_equal spaced, topic.name
      assert_equal spaced, topic.canonical_name
      assert_equal spaced.parameterize, topic.slug
      assert_equal [ glued ], topic.topic_aliases.pluck(:name)
    end
  end

  test "is idempotent when the spaced topic already has the glued alias" do
    topic = Topic.create!(name: "right of way", status: "approved")
    TopicAlias.create!(topic: topic, name: "rightofway")

    @migration.up

    assert_equal "right of way", topic.reload.name
    assert_equal [ "rightofway" ], topic.topic_aliases.pluck(:name)
  end

  test "rolls nothing forward when a spaced name is already taken" do
    glued = Topic.create!(name: "rightofway", status: "approved")
    occupant = Topic.create!(name: "right of way", status: "approved")
    untouched = Topic.create!(name: "selfstoragedevelopment", status: "approved")

    error = assert_raises(RuntimeError) { @migration.up }

    assert_match "Space-fold topic rename aborted", error.message
    assert_match "name is already used by topic #{occupant.id}", error.message
    assert_equal "rightofway", glued.reload.name
    assert_equal "selfstoragedevelopment", untouched.reload.name
    assert_empty glued.topic_aliases
  end

  test "reports canonical name, slug, alias, blocklist, and twin collisions before writing" do
    canonical_topic = Topic.create!(name: "fulltimebuildinginspectorfunding", status: "approved")
    canonical_owner = Topic.create!(name: "inspector staffing study", status: "approved")
    canonical_owner.update_columns(canonical_name: "full time building inspector funding")

    slug_topic = Topic.create!(name: "outofstatemutualaidagreement", status: "approved")
    slug_owner = Topic.create!(name: "mutual aid staffing", status: "approved")
    slug_owner.update_columns(slug: "out-of-state-mutual-aid-agreement")

    alias_topic = Topic.create!(name: "doortodoorsolicitationpermits", status: "approved")
    alias_owner = Topic.create!(name: "solicitation rules", status: "approved")
    TopicAlias.create!(topic: alias_owner, name: "doortodoorsolicitationpermits")

    blocked_topic = Topic.create!(name: "selfimposedmunicipaldebtcap", status: "approved")
    TopicBlocklist.create!(name: "self imposed municipal debt cap", reason: "held")

    spaced_alias_topic = Topic.create!(name: "selfstoragedevelopment", status: "approved")
    spaced_alias_owner = Topic.create!(name: "storage rules", status: "approved")
    TopicAlias.create!(topic: spaced_alias_owner, name: "self storage development")

    twin_a = Topic.create!(name: "trafficsignalsassessmentinspection", status: "approved")
    twin_b = Topic.create!(name: "signal study placeholder", status: "approved")
    twin_b.update_columns(name: "trafficsignalsassessmentinspection")

    error = assert_raises(RuntimeError) { @migration.up }

    assert_match "canonical_name full time building inspector funding", error.message
    assert_match "slug out-of-state-mutual-aid-agreement", error.message
    assert_match "alias doortodoorsolicitationpermits already belongs to topic #{alias_owner.id}", error.message
    assert_match "blocklist contains self imposed municipal debt cap", error.message
    assert_match "alias self storage development already belongs to topic #{spaced_alias_owner.id}", error.message
    assert_match "trafficsignalsassessmentinspection matches 2 topics", error.message
    assert_equal "selfstoragedevelopment", spaced_alias_topic.reload.name
    assert_equal "fulltimebuildinginspectorfunding", canonical_topic.reload.name
    assert_equal "outofstatemutualaidagreement", slug_topic.reload.name
    assert_equal "doortodoorsolicitationpermits", alias_topic.reload.name
    assert_equal "selfimposedmunicipaldebtcap", blocked_topic.reload.name
    assert_equal "trafficsignalsassessmentinspection", twin_a.reload.name
  end

  test "down restores a migrated topic and removes the glued alias" do
    topic = Topic.create!(name: "internalleaksmetertechnology", status: "approved")

    @migration.up
    @migration.down

    assert_equal "internalleaksmetertechnology", topic.reload.name
    assert_equal "internalleaksmetertechnology", topic.canonical_name
    assert_empty topic.topic_aliases
  end

  test "down leaves a spaced topic alone when it has no glued alias" do
    topic = Topic.create!(name: "right of way", status: "approved")

    @migration.down

    assert_equal "right of way", topic.reload.name
    assert_empty topic.topic_aliases
  end
end
