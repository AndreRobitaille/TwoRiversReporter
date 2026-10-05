# Drain workers still running the previous normalizer before this migration.
# Those workers strip hyphens and slashes, so they can insert a glued twin
# while these rows are renamed. After deploy, check for topics whose names
# are the space-stripped forms of the spaced names below.
class SpaceFoldGluedTopicNames < ActiveRecord::Migration[8.1]
  RENAMES = {
    "doortodoorsolicitationpermits" => "door to door solicitation permits",
    "electricutilitylongtermpowersupplycontractwppi" => "electric utility long term power supply contract wppi",
    "fulltimebuildinginspectorfunding" => "full time building inspector funding",
    "outofstatemutualaidagreement" => "out of state mutual aid agreement",
    "rightofway" => "right of way",
    "rightofwayuseforsmallredevelopmentconstructionstaging" => "right of way use for small redevelopment construction staging",
    "rightofwayusepermits" => "right of way use permits",
    "selfimposedmunicipaldebtcap" => "self imposed municipal debt cap",
    "selfstoragedevelopment" => "self storage development",
    "internalleaksmetertechnology" => "internal leaks meter technology",
    "trafficsignalsassessmentinspection" => "traffic signals assessment inspection"
  }.freeze

  def up
    Topic.transaction do
      errors = collision_errors
      raise "Space-fold topic rename aborted:\n#{errors.join("\n")}" if errors.any?

      RENAMES.each do |glued, spaced|
        rename_topic!(glued, spaced)
      end
    end
  end

  def down
    RENAMES.each do |glued, spaced|
      restore_topic!(glued, spaced)
    end
  end

  def collision_errors
    errors = []

    RENAMES.each do |glued, spaced|
      matches = topics_named(glued).to_a
      if matches.size > 1
        errors << "#{glued} matches #{matches.size} topics (#{matches.map(&:id).join(", ")}); resolve the glued twin before migrating"
        next
      end

      topic = matches.first
      next unless topic

      spaced_name = Topic.normalize_name(spaced)
      errors.concat(name_collisions(topic, glued, spaced_name))
      errors.concat(alias_collisions(topic, glued, spaced_name))
      errors.concat(blocklist_collisions(topic, glued, spaced_name))
    end

    errors
  end

  private

  def topics_named(name)
    Topic.where("LOWER(topics.name) = ?", name)
  end

  def name_collisions(topic, glued, spaced_name)
    errors = []
    slug = spaced_name.parameterize

    other_named = topics_named(spaced_name).where.not(id: topic.id)
    if other_named.exists?
      errors << "topic #{topic.id} (#{glued}) cannot become #{spaced_name}; name is already used by topic #{other_named.pick(:id)}"
    end

    other_canonical = Topic.where(canonical_name: spaced_name).where.not(id: topic.id)
    if other_canonical.exists?
      errors << "topic #{topic.id} (#{glued}) cannot take canonical_name #{spaced_name}; topic #{other_canonical.pick(:id)} already has it"
    end

    other_slug = Topic.where(slug: slug).where.not(id: topic.id)
    if other_slug.exists?
      errors << "topic #{topic.id} (#{glued}) cannot take slug #{slug}; topic #{other_slug.pick(:id)} already has it"
    end

    errors
  end

  def alias_collisions(topic, glued, spaced_name)
    errors = []

    other_glued_alias = TopicAlias.where("LOWER(name) = ?", glued).where.not(topic_id: topic.id)
    if other_glued_alias.exists?
      errors << "alias #{glued} already belongs to topic #{other_glued_alias.pick(:topic_id)}"
    end

    other_spaced_alias = TopicAlias.where("LOWER(name) = ?", spaced_name).where.not(topic_id: topic.id)
    if other_spaced_alias.exists?
      errors << "alias #{spaced_name} already belongs to topic #{other_spaced_alias.pick(:topic_id)}"
    end

    errors
  end

  def blocklist_collisions(topic, glued, spaced_name)
    blocked = TopicBlocklist.where("LOWER(name) IN (?)", [ glued, spaced_name ]).pluck(:name)
    return [] if blocked.empty?

    [ "blocklist contains #{blocked.join(", ")}, which would shadow topic #{topic.id} (#{glued})" ]
  end

  def rename_topic!(glued, spaced)
    topic = topics_named(glued).first
    return unless topic

    spaced_name = Topic.normalize_name(spaced)
    topic.update!(name: spaced_name)
    unless topic.topic_aliases.where("LOWER(name) = ?", glued).exists?
      topic.topic_aliases.create!(name: glued)
    end
    say "Renamed topic #{topic.id} from #{glued.inspect} to #{spaced_name.inspect} and kept the glued name as an alias"
  end

  def restore_topic!(glued, spaced)
    topic = topics_named(Topic.normalize_name(spaced)).first
    return unless topic

    legacy_alias = topic.topic_aliases.find_by("LOWER(name) = ?", glued)
    return unless legacy_alias

    legacy_alias.destroy!
    topic.update!(name: glued)
  end
end
