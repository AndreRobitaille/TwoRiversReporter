# Committees & Boards Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace free-form `body_name` strings with a structured Committee model, seed all Two Rivers committees, inject committee context into AI prompts, and provide admin CRUD.

**Architecture:** New `Committee`, `CommitteeAlias`, and `CommitteeMembership` models. Meetings and TopicAppearances gain a `committee_id` FK alongside existing `body_name`. AI prompts get dynamically-built committee context instead of hardcoded `<local_governance>` notes. Admin CRUD follows existing KnowledgeSource patterns.

**Tech Stack:** Rails 8.1, PostgreSQL, Minitest, Turbo/Stimulus

**Design doc:** `docs/plans/2026-02-28-committees-design.md`

---

### Task 1: Migration — Create committees, committee_aliases, committee_memberships tables

**Files:**
- Create: `db/migrate/TIMESTAMP_create_committees_and_related_tables.rb`

**Step 1: Generate and write the migration**

Run: `bin/rails generate migration CreateCommitteesAndRelatedTables`

Then replace the generated migration body with:

```ruby
class CreateCommitteesAndRelatedTables < ActiveRecord::Migration[8.1]
  def change
    create_table :committees do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :committee_type, null: false, default: "city"
      t.string :status, null: false, default: "active"
      t.date :established_on
      t.date :dissolved_on

      t.timestamps
    end

    add_index :committees, :name, unique: true
    add_index :committees, :slug, unique: true

    create_table :committee_aliases do |t|
      t.references :committee, null: false, foreign_key: true
      t.string :name, null: false

      t.timestamps
    end

    add_index :committee_aliases, :name, unique: true

    create_table :committee_memberships do |t|
      t.references :committee, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :role
      t.date :started_on
      t.date :ended_on
      t.string :source, null: false, default: "admin_manual"

      t.timestamps
    end

    add_index :committee_memberships, [:committee_id, :member_id, :ended_on],
              name: "idx_committee_memberships_unique_active",
              unique: true,
              where: "ended_on IS NULL"

    add_reference :meetings, :committee, foreign_key: true, null: true
    add_reference :topic_appearances, :committee, foreign_key: true, null: true
  end
end
```

**Step 2: Run migration**

Run: `bin/rails db:migrate`

Expected: Migration runs cleanly, schema.rb updated with new tables and columns.

**Step 3: Commit**

```bash
git add db/migrate/*_create_committees_and_related_tables.rb db/schema.rb
git commit -m "$(cat <<'EOF'
feat: create committees, committee_aliases, committee_memberships tables

Add committee_id FK to meetings and topic_appearances.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Committee model with validations and slug generation

**Files:**
- Create: `app/models/committee.rb`
- Create: `test/models/committee_test.rb`

**Step 1: Write the failing tests**

Create `test/models/committee_test.rb`:

```ruby
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
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/committee_test.rb`

Expected: All tests fail (Committee class not defined).

**Step 3: Write the Committee model**

Create `app/models/committee.rb`:

```ruby
class Committee < ApplicationRecord
  has_many :committee_aliases, dependent: :destroy
  has_many :committee_memberships, dependent: :destroy
  has_many :members, through: :committee_memberships
  has_many :meetings, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :slug, presence: true, uniqueness: true
  validates :committee_type, inclusion: { in: %w[city tax_funded_nonprofit external] }
  validates :status, inclusion: { in: %w[active dormant dissolved] }

  before_validation :generate_slug

  scope :active, -> { where(status: "active") }
  scope :dormant, -> { where(status: "dormant") }

  # Active and dormant committees with descriptions — used for AI prompt context
  scope :for_ai_context, -> { where(status: %w[active dormant]).where.not(description: [nil, ""]).order(:name) }

  # Resolve a scraped body_name to a Committee record.
  # Checks canonical name first, then aliases.
  def self.resolve(body_name)
    return nil if body_name.blank?
    find_by(name: body_name) || CommitteeAlias.find_by(name: body_name)&.committee
  end

  private

  def generate_slug
    self.slug = name.parameterize if name.present? && (slug.blank? || name_changed?)
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/committee_test.rb`

Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/committee.rb test/models/committee_test.rb
git commit -m "$(cat <<'EOF'
feat: add Committee model with validations, scopes, and resolve

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: CommitteeAlias model

**Files:**
- Create: `app/models/committee_alias.rb`
- Create: `test/models/committee_alias_test.rb`

**Step 1: Write the failing tests**

Create `test/models/committee_alias_test.rb`:

```ruby
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
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/committee_alias_test.rb`

Expected: All tests fail.

**Step 3: Write the CommitteeAlias model**

Create `app/models/committee_alias.rb`:

```ruby
class CommitteeAlias < ApplicationRecord
  belongs_to :committee

  validates :name, presence: true, uniqueness: true

  before_validation :normalize_name

  private

  def normalize_name
    self.name = name.to_s.strip.squish if name.present?
  end
end
```

**Step 4: Run tests to verify they pass**

Run: `bin/rails test test/models/committee_alias_test.rb`

Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/models/committee_alias.rb test/models/committee_alias_test.rb
git commit -m "$(cat <<'EOF'
feat: add CommitteeAlias model

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: CommitteeMembership model

**Files:**
- Create: `app/models/committee_membership.rb`
- Create: `test/models/committee_membership_test.rb`
- Modify: `app/models/member.rb` — add `has_many :committee_memberships` and `has_many :committees`

**Step 1: Write the failing tests**

Create `test/models/committee_membership_test.rb`:

```ruby
require "test_helper"

class CommitteeMembershipTest < ActiveSupport::TestCase
  setup do
    @committee = Committee.create!(name: "City Council")
    @member = Member.create!(name: "Jane Doe")
  end

  test "valid membership saves" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, role: "member")
    assert membership.save
  end

  test "committee is required" do
    membership = CommitteeMembership.new(member: @member)
    assert_not membership.valid?
  end

  test "member is required" do
    membership = CommitteeMembership.new(committee: @committee)
    assert_not membership.valid?
  end

  test "role validates inclusion when present" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, role: "dictator")
    assert_not membership.valid?
  end

  test "role can be nil" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, role: nil)
    assert membership.valid?
  end

  test "source defaults to admin_manual" do
    membership = CommitteeMembership.create!(committee: @committee, member: @member)
    assert_equal "admin_manual", membership.source
  end

  test "source validates inclusion" do
    membership = CommitteeMembership.new(committee: @committee, member: @member, source: "magic")
    assert_not membership.valid?
  end

  test "current scope returns memberships without end date" do
    current = CommitteeMembership.create!(committee: @committee, member: @member)
    ended = CommitteeMembership.create!(
      committee: @committee,
      member: Member.create!(name: "Past Member"),
      ended_on: 1.month.ago
    )

    assert_includes CommitteeMembership.current, current
    assert_not_includes CommitteeMembership.current, ended
  end

  test "member has committees through memberships" do
    CommitteeMembership.create!(committee: @committee, member: @member)
    assert_includes @member.committees, @committee
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/committee_membership_test.rb`

Expected: All tests fail.

**Step 3: Write the CommitteeMembership model**

Create `app/models/committee_membership.rb`:

```ruby
class CommitteeMembership < ApplicationRecord
  belongs_to :committee
  belongs_to :member

  ROLES = %w[chair vice_chair member secretary alternate].freeze
  SOURCES = %w[ai_extracted admin_manual seeded].freeze

  validates :role, inclusion: { in: ROLES }, allow_nil: true
  validates :source, inclusion: { in: SOURCES }

  scope :current, -> { where(ended_on: nil) }
end
```

**Step 4: Add associations to Member model**

Modify `app/models/member.rb`:

```ruby
class Member < ApplicationRecord
  has_many :votes, dependent: :destroy
  has_many :committee_memberships, dependent: :destroy
  has_many :committees, through: :committee_memberships

  validates :name, presence: true, uniqueness: true
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/models/committee_membership_test.rb`

Expected: All tests pass.

**Step 6: Commit**

```bash
git add app/models/committee_membership.rb app/models/member.rb test/models/committee_membership_test.rb
git commit -m "$(cat <<'EOF'
feat: add CommitteeMembership model, wire Member associations

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Update Meeting and TopicAppearance models

**Files:**
- Modify: `app/models/meeting.rb` — add `belongs_to :committee`
- Modify: `app/models/topic_appearance.rb` — add `belongs_to :committee`
- Modify: `app/models/agenda_item_topic.rb` — copy `committee_id` alongside `body_name`
- Create: `test/models/meeting_committee_test.rb`

**Step 1: Write the failing tests**

Create `test/models/meeting_committee_test.rb`:

```ruby
require "test_helper"

class MeetingCommitteeTest < ActiveSupport::TestCase
  test "meeting can belong to a committee" do
    committee = Committee.create!(name: "City Council")
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/meeting/1",
      body_name: "City Council Meeting",
      committee: committee,
      starts_at: 1.day.ago
    )
    assert_equal committee, meeting.committee
  end

  test "meeting committee is optional" do
    meeting = Meeting.new(
      detail_page_url: "https://example.com/meeting/2",
      body_name: "Unknown Body",
      starts_at: 1.day.ago
    )
    assert meeting.valid?
    assert_nil meeting.committee
  end

  test "topic appearance gets committee_id from meeting via agenda_item_topic" do
    committee = Committee.create!(name: "Plan Commission")
    meeting = Meeting.create!(
      detail_page_url: "https://example.com/meeting/3",
      body_name: "Plan Commission",
      committee: committee,
      starts_at: 1.day.ago
    )
    agenda_item = meeting.agenda_items.create!(title: "Test Item")
    topic = Topic.create!(name: "test topic", status: "approved")

    AgendaItemTopic.create!(agenda_item: agenda_item, topic: topic)

    appearance = TopicAppearance.last
    assert_equal committee, appearance.committee
    assert_equal "Plan Commission", appearance.body_name
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/meeting_committee_test.rb`

Expected: Tests fail (no committee association on Meeting).

**Step 3: Update Meeting model**

Add to `app/models/meeting.rb`, after existing associations:

```ruby
belongs_to :committee, optional: true
```

**Step 4: Update TopicAppearance model**

Add to `app/models/topic_appearance.rb`, after existing associations:

```ruby
belongs_to :committee, optional: true
```

**Step 5: Update AgendaItemTopic to copy committee_id**

In `app/models/agenda_item_topic.rb`, in the `create_appearance_and_update_continuity` method, add `committee: meeting.committee` to the `TopicAppearance.create!` call. The line that creates the appearance should become:

```ruby
TopicAppearance.create!(
  topic: topic,
  meeting: meeting,
  agenda_item: agenda_item,
  appeared_at: meeting.starts_at || agenda_item.created_at,
  body_name: meeting.body_name,
  committee: meeting.committee,
  evidence_type: "agenda_item",
  source_ref: { agenda_item_id: agenda_item.id, title: agenda_item.title }
)
```

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/models/meeting_committee_test.rb`

Expected: All tests pass.

**Step 7: Run full test suite**

Run: `bin/rails test`

Expected: No regressions. Existing tests still pass since committee is optional.

**Step 8: Commit**

```bash
git add app/models/meeting.rb app/models/topic_appearance.rb app/models/agenda_item_topic.rb test/models/meeting_committee_test.rb
git commit -m "$(cat <<'EOF'
feat: wire committee associations on Meeting, TopicAppearance, AgendaItemTopic

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Seed committees data

**Files:**
- Create: `db/seeds/committees.rb`
- Modify: `db/seeds.rb` — add `load` for committees seed

**Step 1: Create the seed file**

Create `db/seeds/committees.rb` with all 25 committees from the user's document. Each committee gets: name, description, committee_type, status. Include aliases for known name variants. Include `CommitteeAlias` entries to map scraped body_name values (e.g., "City Council Meeting" → "City Council").

```ruby
# Seed committees and boards for Two Rivers, WI

committees_data = [
  {
    name: "City Council",
    description: "Exercises all legislative and general ordinance powers under Wisconsin's council-manager form of government. Sets policy; the city manager handles execution.",
    committee_type: "city",
    status: "active",
    aliases: ["City Council Meeting"]
  },
  {
    name: "Advisory Recreation Board",
    description: "Recommends improvements to city parks and recreational programs.",
    committee_type: "city",
    status: "active",
    aliases: ["Advisory Recreation Board Meeting", "ARB"]
  },
  {
    name: "Board of Appeals",
    description: "Reviews appeals of official enforcement decisions, handles requests for exceptions to local ordinances, and can approve limited variances.",
    committee_type: "city",
    status: "active",
    aliases: ["Board of Appeals Meeting"]
  },
  {
    name: "Board of Canvassers",
    description: "Checks, confirms, and officially certifies election results.",
    committee_type: "city",
    status: "active",
    aliases: ["Board of Canvassers Meeting"]
  },
  {
    name: "Board of Education",
    description: "State-jurisdiction board overseeing public schools. Not under city control. Sets educational policies, manages district budget, hires superintendent.",
    committee_type: "external",
    status: "active",
    aliases: ["Board of Education Meeting"]
  },
  {
    name: "Branding and Marketing Committee",
    description: "Advises on community branding and marketing strategies for residential, commercial, industrial, and tourism promotion.",
    committee_type: "city",
    status: "dormant",
    aliases: ["Branding and Marketing Committee Meeting"]
  },
  {
    name: "Business and Industrial Development Committee",
    description: "Advises on industrial development, promotes the city's industrial advantages, and recommends use of city properties for industrial purposes. Same membership as CDA; meets concurrently.",
    committee_type: "city",
    status: "active",
    aliases: ["Business and Industrial Development Committee Meeting", "BIDC", "BIDC Meeting"]
  },
  {
    name: "Business Improvement District Board",
    description: "Works to retain, expand, and attract businesses of all sizes to Two Rivers.",
    committee_type: "city",
    status: "active",
    aliases: ["Business Improvement District Board Meeting", "BID Board", "BID Board Meeting"]
  },
  {
    name: "Central Park West 365 Planning Committee",
    description: "Planned a centrally located public space on Washington Street/STH 42 with splash pad and ice rink. Originally the Splash Pad and Ice Rink Planning Committee. Mission complete.",
    committee_type: "city",
    status: "dissolved",
    aliases: [
      "Central Park West 365 Planning Committee Meeting",
      "Splash Pad and Ice Rink Planning Committee",
      "Splash Pad and Ice Rink Planning Committee Meeting"
    ]
  },
  {
    name: "Commission for Equal Opportunities in Housing",
    description: "Enforces Fair Housing Act and related laws to ensure equal access to housing without discrimination.",
    committee_type: "city",
    status: "dormant",
    aliases: ["Commission for Equal Opportunities in Housing Meeting"]
  },
  {
    name: "Committee on Aging",
    description: "Identifies concerns of older citizens and advises the Advisory Recreation Board and city manager on senior citizen issues. Primarily an update/input committee.",
    committee_type: "city",
    status: "active",
    aliases: ["Committee on Aging Meeting"]
  },
  {
    name: "Community Development Authority",
    description: "Leads blight elimination, urban renewal, and housing/redevelopment projects. Acts as the city's redevelopment agent. Same membership as BIDC; meets concurrently.",
    committee_type: "city",
    status: "active",
    aliases: ["Community Development Authority Meeting", "CDA", "CDA Meeting"]
  },
  {
    name: "Environmental Advisory Board",
    description: "Advises the public works committee on environmental protection, sustainability, and resiliency policies.",
    committee_type: "city",
    status: "active",
    aliases: ["Environmental Advisory Board Meeting", "EAB", "EAB Meeting"]
  },
  {
    name: "Explore Two Rivers Board of Directors",
    description: "Nonprofit promoting overnight tourism. Operates using room tax revenues in compliance with Wisconsin tourism promotion laws. Funded through Room Tax Commission allocations.",
    committee_type: "tax_funded_nonprofit",
    status: "active",
    aliases: ["Explore Two Rivers Board of Directors Meeting", "Explore Two Rivers Meeting"]
  },
  {
    name: "Library Board of Trustees",
    description: "Oversees public library management and policy. Has exclusive control over library funds, property, and staffing including appointing the library director.",
    committee_type: "city",
    status: "active",
    aliases: ["Library Board of Trustees Meeting"]
  },
  {
    name: "Main Street Board of Directors",
    description: "Nonprofit funded through Business Improvement District special assessments. Manages downtown facade improvements, streetscaping, events, and business support.",
    committee_type: "tax_funded_nonprofit",
    status: "active",
    aliases: ["Main Street Board of Directors Meeting", "Main Street Board Meeting"]
  },
  {
    name: "Personnel and Finance Committee",
    description: "Oversees city personnel policies and financial matters including budgets, salaries, and fiscal management.",
    committee_type: "city",
    status: "active",
    aliases: ["Personnel and Finance Committee Meeting"]
  },
  {
    name: "Plan Commission",
    description: "Develops the city's comprehensive plan for physical development. Reviews and recommends on public buildings, land acquisitions, plats, and zoning matters.",
    committee_type: "city",
    status: "active",
    aliases: ["Plan Commission Meeting"]
  },
  {
    name: "Police and Fire Commission",
    description: "Oversees appointment, promotion, discipline, and dismissal of Police and Fire Chiefs and subordinates.",
    committee_type: "city",
    status: "active",
    aliases: ["Police and Fire Commission Meeting", "PFC", "PFC Meeting"]
  },
  {
    name: "Public Utilities Committee",
    description: "Provides oversight on city utility operations including water, sewer, and electricity.",
    committee_type: "city",
    status: "active",
    aliases: ["Public Utilities Committee Meeting"]
  },
  {
    name: "Public Works Committee",
    description: "Reviews and advises on infrastructure projects, city facility maintenance, and public works operations including roads, drainage, and sanitation.",
    committee_type: "city",
    status: "active",
    aliases: ["Public Works Committee Meeting"]
  },
  {
    name: "Room Tax Commission",
    description: "Manages and allocates room tax revenues from lodging facilities. At least 70% must fund tourism; remainder available for other city needs.",
    committee_type: "city",
    status: "active",
    aliases: ["Room Tax Commission Meeting"]
  },
  {
    name: "Two Rivers Business Association",
    description: "Nonprofit supporting business growth on the Lakeshore. Provides networking, fosters community, and raises public awareness. Not a city government board.",
    committee_type: "external",
    status: "active",
    aliases: ["Two Rivers Business Association Meeting", "TRBA", "TRBA Meeting"]
  },
  {
    name: "Zoning Board",
    description: "Reviews zoning appeals, special exceptions, and variances. Handles cases where property owners seek relief from zoning ordinance requirements.",
    committee_type: "city",
    status: "active",
    aliases: ["Zoning Board Meeting", "Zoning Board of Appeals", "Zoning Board of Appeals Meeting"]
  }
]

committees_data.each do |data|
  aliases = data.delete(:aliases) || []

  committee = Committee.find_or_create_by!(name: data[:name]) do |c|
    c.assign_attributes(data)
  end

  aliases.each do |alias_name|
    CommitteeAlias.find_or_create_by!(name: alias_name) do |a|
      a.committee = committee
    end
  end
end

Rails.logger.info "Seeded #{Committee.count} committees with #{CommitteeAlias.count} aliases."
```

**Step 2: Add load to seeds.rb**

Add to the end of `db/seeds.rb`:

```ruby
load Rails.root.join("db/seeds/committees.rb")
```

**Step 3: Run seeds**

Run: `bin/rails db:seed`

Expected: 24 committees created with aliases. No errors.

**Step 4: Verify in console**

Run: `bin/rails runner "puts \"#{Committee.count} committees, #{CommitteeAlias.count} aliases\""`

Expected: `24 committees, XX aliases`

**Step 5: Commit**

```bash
git add db/seeds/committees.rb db/seeds.rb
git commit -m "$(cat <<'EOF'
feat: seed 24 Two Rivers committees with aliases

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 7: Backfill committee_id on existing meetings and topic_appearances

**Files:**
- Create: `db/migrate/TIMESTAMP_backfill_committee_ids.rb`

**Step 1: Create a data migration**

Run: `bin/rails generate migration BackfillCommitteeIds`

Replace the body with:

```ruby
class BackfillCommitteeIds < ActiveRecord::Migration[8.1]
  def up
    # Backfill meetings
    Meeting.find_each do |meeting|
      next if meeting.committee_id.present? || meeting.body_name.blank?
      committee = Committee.resolve(meeting.body_name)
      meeting.update_column(:committee_id, committee.id) if committee
    end

    # Backfill topic_appearances from their meetings
    TopicAppearance.includes(:meeting).find_each do |appearance|
      next if appearance.committee_id.present?
      if appearance.meeting&.committee_id.present?
        appearance.update_column(:committee_id, appearance.meeting.committee_id)
      elsif appearance.body_name.present?
        committee = Committee.resolve(appearance.body_name)
        appearance.update_column(:committee_id, committee.id) if committee
      end
    end
  end

  def down
    Meeting.update_all(committee_id: nil)
    TopicAppearance.update_all(committee_id: nil)
  end
end
```

**Step 2: Run migration**

Run: `bin/rails db:migrate`

Expected: Existing meetings and appearances get committee_id populated.

**Step 3: Verify backfill**

Run: `bin/rails runner "puts \"Meetings with committee: #{Meeting.where.not(committee_id: nil).count}/#{Meeting.count}\"; puts \"Unmatched: #{Meeting.where(committee_id: nil).where.not(body_name: nil).pluck(:body_name).uniq.join(', ')}\""`

Expected: Most meetings matched. Any unmatched body_names are printed — add aliases for those if needed.

**Step 4: Commit**

```bash
git add db/migrate/*_backfill_committee_ids.rb db/schema.rb
git commit -m "$(cat <<'EOF'
feat: backfill committee_id on meetings and topic_appearances

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 8: Update scraper to set committee_id

**Files:**
- Modify: `app/jobs/scrapers/discover_meetings_job.rb`
- Create: `test/jobs/scrapers/discover_meetings_committee_test.rb`

**Step 1: Write the failing test**

Create `test/jobs/scrapers/discover_meetings_committee_test.rb`:

```ruby
require "test_helper"

class Scrapers::DiscoverMeetingsCommitteeTest < ActiveSupport::TestCase
  test "sets committee_id when body_name matches a committee" do
    committee = Committee.create!(name: "City Council")
    CommitteeAlias.create!(committee: committee, name: "City Council Meeting")

    meeting = Meeting.create!(
      detail_page_url: "https://example.com/meeting/1",
      body_name: "City Council Meeting",
      starts_at: 1.day.ago
    )

    resolved = Committee.resolve(meeting.body_name)
    assert_equal committee, resolved
  end

  test "resolve returns nil for unrecognized body_name" do
    assert_nil Committee.resolve("Totally Unknown Board Meeting")
  end
end
```

**Step 2: Run tests to verify they pass** (these test the resolve method)

Run: `bin/rails test test/jobs/scrapers/discover_meetings_committee_test.rb`

Expected: Tests pass (resolve already implemented in Task 2).

**Step 3: Update DiscoverMeetingsJob**

In `app/jobs/scrapers/discover_meetings_job.rb`, after line 67 (`meeting.body_name = title_text`), add:

```ruby
meeting.committee = Committee.resolve(title_text)
```

And add a warning log if unresolved. After line 69 (`meeting.status = determine_status(starts_at)`), add:

```ruby
if meeting.committee_id.blank? && meeting.body_name.present?
  Rails.logger.warn "DiscoverMeetingsJob: No committee match for body_name='#{meeting.body_name}'"
end
```

**Step 4: Run full test suite**

Run: `bin/rails test`

Expected: All tests pass.

**Step 5: Commit**

```bash
git add app/jobs/scrapers/discover_meetings_job.rb test/jobs/scrapers/discover_meetings_committee_test.rb
git commit -m "$(cat <<'EOF'
feat: scraper resolves body_name to committee_id

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 9: AI prompt injection — prepare_committee_context

**Files:**
- Modify: `app/services/ai/open_ai_service.rb`
- Create: `test/services/ai/committee_context_test.rb`

**Step 1: Write the failing test**

Create `test/services/ai/committee_context_test.rb`:

```ruby
require "test_helper"

class Ai::CommitteeContextTest < ActiveSupport::TestCase
  test "prepare_committee_context includes active committees with descriptions" do
    Committee.create!(name: "City Council", description: "Legislative body", status: "active")
    Committee.create!(name: "Old Board", description: "Gone now", status: "dissolved")
    Committee.create!(name: "Sleeping Board", description: "Resting", status: "dormant")
    Committee.create!(name: "No Description Board", status: "active")

    service = Ai::OpenAiService.new
    context = service.send(:prepare_committee_context)

    assert_includes context, "City Council"
    assert_includes context, "Legislative body"
    assert_includes context, "Sleeping Board"
    assert_includes context, "Resting"
    assert_not_includes context, "Old Board"
    assert_not_includes context, "No Description Board"
  end

  test "prepare_committee_context returns empty string when no committees" do
    service = Ai::OpenAiService.new
    context = service.send(:prepare_committee_context)
    assert_equal "", context
  end

  test "prepare_committee_context includes committee_type" do
    Committee.create!(name: "Main Street Board", description: "Downtown", committee_type: "tax_funded_nonprofit")

    service = Ai::OpenAiService.new
    context = service.send(:prepare_committee_context)

    assert_includes context, "Tax funded nonprofit"
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/ai/committee_context_test.rb`

Expected: Tests fail (method doesn't exist).

**Step 3: Add prepare_committee_context method to OpenAiService**

Add the following private method to `app/services/ai/open_ai_service.rb`, near the other `prepare_*` helper methods (around line 690, near `prepare_kb_context`):

```ruby
def prepare_committee_context
  committees = Committee.for_ai_context
  return "" if committees.empty?

  lines = committees.map do |c|
    type_label = c.committee_type.humanize
    "- #{c.name} (#{type_label}): #{c.description}"
  end

  <<~CONTEXT
    <local_governance>
    The following committees and boards operate in Two Rivers:
    #{lines.join("\n")}

    Notes:
    - Cross-body movement (topic appearing at different committees) is routine and NOT noteworthy unless City Council sends something BACK DOWN to a subcommittee — that's a signal of disagreement or unresolved issues.
    </local_governance>
  CONTEXT
end
```

**Step 4: Replace the hardcoded `<local_governance>` block in `analyze_topic_briefing`**

In `app/services/ai/open_ai_service.rb`, find the hardcoded `<local_governance>` block (around lines 524-532 in `analyze_topic_briefing`) and replace it with:

```ruby
#{prepare_committee_context}
```

This replaces the static text:
```
<local_governance>
- Cross-body movement (topic appearing at different committees) is routine...
- The Committee on Aging is primarily an update/input committee...
</local_governance>
```

The Committee on Aging note is now captured in its seed description ("Primarily an update/input committee"), so it will appear in the dynamic context.

**Step 5: Inject committee context into other prompts**

Add `#{prepare_committee_context}` into these prompts (before the main content/context):

1. `analyze_topic_summary` (around line 272) — add before `TOPIC CONTEXT (JSON):` line
2. `analyze_meeting_content` (around line 812) — add after `#{kb_context}` line

These are the prompts where committee context is most valuable. The render methods don't need it — they work from the analysis JSON output.

**Step 6: Run tests to verify they pass**

Run: `bin/rails test test/services/ai/committee_context_test.rb`

Expected: All tests pass.

**Step 7: Run full test suite**

Run: `bin/rails test`

Expected: No regressions.

**Step 8: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/committee_context_test.rb
git commit -m "$(cat <<'EOF'
feat: inject dynamic committee context into AI prompts

Replace hardcoded local_governance block with database-driven
committee descriptions.

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 10: Admin committees controller and routes

**Files:**
- Create: `app/controllers/admin/committees_controller.rb`
- Modify: `config/routes.rb` — add committee routes
- Create: `test/controllers/admin/committees_controller_test.rb`

**Step 1: Write the failing tests**

Create `test/controllers/admin/committees_controller_test.rb`:

```ruby
require "test_helper"

class Admin::CommitteesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email_address: "admin@test.com", password: "password", admin: true, totp_enabled: true)
    @admin.ensure_totp_secret!

    post session_url, params: { email_address: "admin@test.com", password: "password" }
    follow_redirect!

    totp = ROTP::TOTP.new(@admin.totp_secret, issuer: "TwoRiversMatters")
    post mfa_session_url, params: { code: totp.now }
    follow_redirect!

    @committee = Committee.create!(
      name: "Plan Commission",
      description: "Zoning and planning",
      committee_type: "city",
      status: "active"
    )
  end

  test "index lists committees" do
    get admin_committees_url
    assert_response :success
    assert_select "a", text: "Plan Commission"
  end

  test "show displays committee details" do
    get admin_committee_url(@committee)
    assert_response :success
    assert_select "h1", text: /Plan Commission/
  end

  test "new renders form" do
    get new_admin_committee_url
    assert_response :success
  end

  test "create saves valid committee" do
    assert_difference "Committee.count", 1 do
      post admin_committees_url, params: {
        committee: { name: "New Board", description: "Does stuff", committee_type: "city", status: "active" }
      }
    end
    assert_redirected_to admin_committee_url(Committee.last)
  end

  test "create rejects invalid committee" do
    assert_no_difference "Committee.count" do
      post admin_committees_url, params: {
        committee: { name: "", description: "No name" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "update modifies committee" do
    patch admin_committee_url(@committee), params: {
      committee: { description: "Updated description" }
    }
    assert_redirected_to admin_committee_url(@committee)
    assert_equal "Updated description", @committee.reload.description
  end

  test "destroy deletes committee" do
    assert_difference "Committee.count", -1 do
      delete admin_committee_url(@committee)
    end
    assert_redirected_to admin_committees_url
  end

  test "create_alias adds alias" do
    assert_difference "CommitteeAlias.count", 1 do
      post create_alias_admin_committee_url(@committee), params: { name: "PC" }
    end
    assert_redirected_to admin_committee_url(@committee)
  end

  test "destroy_alias removes alias" do
    alias_record = CommitteeAlias.create!(committee: @committee, name: "PC")
    assert_difference "CommitteeAlias.count", -1 do
      delete destroy_alias_admin_committee_url(@committee, alias_id: alias_record.id)
    end
    assert_redirected_to admin_committee_url(@committee)
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/controllers/admin/committees_controller_test.rb`

Expected: Tests fail (route/controller not defined).

**Step 3: Add routes**

In `config/routes.rb`, inside the `scope :admin` block, add:

```ruby
resources :committees, controller: "admin/committees", as: :admin_committees do
  member do
    post :create_alias
    delete :destroy_alias
  end
end
```

**Step 4: Create the controller**

Create `app/controllers/admin/committees_controller.rb`:

```ruby
module Admin
  class CommitteesController < BaseController
    before_action :set_committee, only: %i[show edit update destroy create_alias destroy_alias]

    def index
      @committees = Committee.all.order(:name)
      @committees = @committees.where(committee_type: params[:type]) if params[:type].present?
      @committees = @committees.where(status: params[:status]) if params[:status].present?
    end

    def show
      @aliases = @committee.committee_aliases.order(:name)
      @memberships = @committee.committee_memberships.includes(:member).order(ended_on: :desc, started_on: :desc)
    end

    def new
      @committee = Committee.new
    end

    def create
      @committee = Committee.new(committee_params)

      if @committee.save
        redirect_to admin_committee_path(@committee), notice: "Committee created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @committee.update(committee_params)
        redirect_to admin_committee_path(@committee), notice: "Committee updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      @committee.destroy
      redirect_to admin_committees_path, notice: "Committee deleted."
    end

    def create_alias
      @alias = @committee.committee_aliases.build(name: params[:name])

      if @alias.save
        redirect_to admin_committee_path(@committee), notice: "Alias added."
      else
        redirect_to admin_committee_path(@committee), alert: "Failed: #{@alias.errors.full_messages.join(', ')}"
      end
    end

    def destroy_alias
      alias_record = @committee.committee_aliases.find(params[:alias_id])
      alias_record.destroy
      redirect_to admin_committee_path(@committee), notice: "Alias removed."
    end

    private

    def set_committee
      @committee = Committee.find(params[:id])
    end

    def committee_params
      params.require(:committee).permit(:name, :description, :committee_type, :status, :established_on, :dissolved_on)
    end
  end
end
```

**Step 5: Run tests to verify they pass**

Run: `bin/rails test test/controllers/admin/committees_controller_test.rb`

Expected: Tests fail because views don't exist yet (but routes and controller logic are correct). Continue to Task 11 for views.

**Step 6: Commit controller and routes**

```bash
git add app/controllers/admin/committees_controller.rb config/routes.rb test/controllers/admin/committees_controller_test.rb
git commit -m "$(cat <<'EOF'
feat: add admin committees controller with alias management

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 11: Admin committee views

**Files:**
- Create: `app/views/admin/committees/index.html.erb`
- Create: `app/views/admin/committees/show.html.erb`
- Create: `app/views/admin/committees/new.html.erb`
- Create: `app/views/admin/committees/edit.html.erb`
- Create: `app/views/admin/committees/_form.html.erb`

**Step 1: Create index view**

Create `app/views/admin/committees/index.html.erb`:

```erb
<% content_for(:title) { "Committees - Admin" } %>

<div class="page-header">
  <div class="flex justify-between items-center">
    <div>
      <h1 class="page-title">Committees & Boards</h1>
      <p class="page-subtitle">Manage governing bodies and their descriptions for AI context.</p>
    </div>
    <%= link_to "New Committee", new_admin_committee_path, class: "btn btn--primary" %>
  </div>
</div>

<div class="flex gap-2 mb-4">
  <%= link_to "All", admin_committees_path, class: "btn btn--sm #{params[:type].blank? && params[:status].blank? ? 'btn--primary' : 'btn--ghost'}" %>
  <%= link_to "City", admin_committees_path(type: "city"), class: "btn btn--sm #{params[:type] == 'city' ? 'btn--primary' : 'btn--ghost'}" %>
  <%= link_to "Tax-Funded Nonprofit", admin_committees_path(type: "tax_funded_nonprofit"), class: "btn btn--sm #{params[:type] == 'tax_funded_nonprofit' ? 'btn--primary' : 'btn--ghost'}" %>
  <%= link_to "External", admin_committees_path(type: "external"), class: "btn btn--sm #{params[:type] == 'external' ? 'btn--primary' : 'btn--ghost'}" %>
  <span class="mx-2 border-l"></span>
  <%= link_to "Active", admin_committees_path(status: "active"), class: "btn btn--sm #{params[:status] == 'active' ? 'btn--primary' : 'btn--ghost'}" %>
  <%= link_to "Dormant", admin_committees_path(status: "dormant"), class: "btn btn--sm #{params[:status] == 'dormant' ? 'btn--primary' : 'btn--ghost'}" %>
  <%= link_to "Dissolved", admin_committees_path(status: "dissolved"), class: "btn btn--sm #{params[:status] == 'dissolved' ? 'btn--primary' : 'btn--ghost'}" %>
</div>

<div class="table-wrapper">
  <table>
    <thead>
      <tr>
        <th>Name</th>
        <th>Type</th>
        <th>Status</th>
        <th>Meetings</th>
        <th>Aliases</th>
        <th></th>
      </tr>
    </thead>
    <tbody>
      <% @committees.each do |committee| %>
        <tr>
          <td>
            <strong><%= link_to committee.name, admin_committee_path(committee) %></strong>
            <% if committee.description.present? %>
              <p class="text-sm text-secondary mt-1 mb-0"><%= truncate(committee.description, length: 80) %></p>
            <% end %>
          </td>
          <td>
            <span class="badge badge--default"><%= committee.committee_type.humanize %></span>
          </td>
          <td>
            <% case committee.status %>
            <% when "active" %>
              <span class="badge badge--success">Active</span>
            <% when "dormant" %>
              <span class="badge badge--warning">Dormant</span>
            <% when "dissolved" %>
              <span class="badge badge--default">Dissolved</span>
            <% end %>
          </td>
          <td><%= committee.meetings.count %></td>
          <td><%= committee.committee_aliases.count %></td>
          <td class="text-right">
            <%= link_to "Edit", edit_admin_committee_path(committee), class: "btn btn--sm btn--ghost" %>
          </td>
        </tr>
      <% end %>
    </tbody>
  </table>
</div>
```

**Step 2: Create form partial**

Create `app/views/admin/committees/_form.html.erb`:

```erb
<%= form_with model: [:admin, committee] do |form| %>
  <% if committee.errors.any? %>
    <div class="flash flash--danger">
      <%= committee.errors.full_messages.to_sentence %>
    </div>
  <% end %>

  <div class="form-group">
    <%= form.label :name, class: "form-label" %>
    <%= form.text_field :name, class: "form-input", placeholder: "e.g. Plan Commission" %>
  </div>

  <div class="form-group">
    <%= form.label :description, class: "form-label" %>
    <%= form.text_area :description, rows: 4, class: "form-textarea",
        placeholder: "Purpose and mandate — this is injected into AI prompts as context." %>
    <p class="text-sm text-muted mt-1">Describe what this committee does. This text is provided to the AI when generating meeting and topic summaries.</p>
  </div>

  <div class="flex gap-4">
    <div class="form-group grow">
      <%= form.label :committee_type, "Type", class: "form-label" %>
      <%= form.select :committee_type, [
        ["City Board/Commission", "city"],
        ["Tax-Funded Nonprofit", "tax_funded_nonprofit"],
        ["External (Non-City)", "external"]
      ], {}, class: "form-select" %>
    </div>

    <div class="form-group grow">
      <%= form.label :status, class: "form-label" %>
      <%= form.select :status, [
        ["Active", "active"],
        ["Dormant", "dormant"],
        ["Dissolved", "dissolved"]
      ], {}, class: "form-select" %>
    </div>
  </div>

  <div class="flex gap-4">
    <div class="form-group grow">
      <%= form.label :established_on, "Established", class: "form-label" %>
      <%= form.date_field :established_on, class: "form-input" %>
    </div>

    <div class="form-group grow">
      <%= form.label :dissolved_on, "Dissolved", class: "form-label" %>
      <%= form.date_field :dissolved_on, class: "form-input" %>
    </div>
  </div>

  <div class="flex gap-2 items-center mt-6">
    <%= form.submit class: "btn btn--primary" %>
    <%= link_to "Cancel", admin_committees_path, class: "btn btn--secondary" %>
  </div>
<% end %>
```

**Step 3: Create new and edit views**

Create `app/views/admin/committees/new.html.erb`:

```erb
<% content_for(:title) { "New Committee - Admin" } %>

<div class="card card--narrow">
  <div class="card-header">
    <h1 class="card-title">New Committee</h1>
  </div>
  <%= render "form", committee: @committee %>
</div>
```

Create `app/views/admin/committees/edit.html.erb`:

```erb
<% content_for(:title) { "Edit #{@committee.name} - Admin" } %>

<div class="card card--narrow">
  <div class="card-header">
    <h1 class="card-title">Edit Committee</h1>
  </div>
  <%= render "form", committee: @committee %>
</div>
```

**Step 4: Create show view**

Create `app/views/admin/committees/show.html.erb`:

```erb
<% content_for(:title) { "#{@committee.name} - Admin" } %>

<div class="page-header">
  <div class="flex justify-between items-center">
    <div>
      <div class="flex items-center gap-2 mb-2">
        <%= link_to "Committees", admin_committees_path, class: "text-secondary hover:underline" %>
        <span class="text-muted">/</span>
        <h1 class="page-title mb-0"><%= @committee.name %></h1>
      </div>
      <div class="flex gap-2">
        <span class="badge badge--default"><%= @committee.committee_type.humanize %></span>
        <% case @committee.status %>
        <% when "active" %>
          <span class="badge badge--success">Active</span>
        <% when "dormant" %>
          <span class="badge badge--warning">Dormant</span>
        <% when "dissolved" %>
          <span class="badge badge--default">Dissolved</span>
        <% end %>
      </div>
    </div>
    <div class="flex gap-2">
      <%= link_to "Edit", edit_admin_committee_path(@committee), class: "btn btn--primary" %>
      <%= button_to "Delete", admin_committee_path(@committee), method: :delete,
          class: "btn btn--danger", form: { data: { turbo_confirm: "Delete this committee?" } } %>
    </div>
  </div>
</div>

<% if @committee.description.present? %>
  <div class="card p-6 mb-6">
    <h2 class="text-lg font-bold mb-2">Description</h2>
    <p class="text-secondary"><%= @committee.description %></p>
    <% if @committee.established_on.present? || @committee.dissolved_on.present? %>
      <div class="flex gap-4 mt-4 text-sm text-muted">
        <% if @committee.established_on.present? %>
          <span>Established: <%= @committee.established_on %></span>
        <% end %>
        <% if @committee.dissolved_on.present? %>
          <span>Dissolved: <%= @committee.dissolved_on %></span>
        <% end %>
      </div>
    <% end %>
  </div>
<% end %>

<div class="card p-6 mb-6">
  <h2 class="text-lg font-bold mb-4">Aliases</h2>
  <p class="text-sm text-secondary mb-4">Name variants used by the scraper to match this committee. Historical names map old meetings to this committee.</p>

  <% if @aliases.any? %>
    <table class="mb-4">
      <tbody>
        <% @aliases.each do |a| %>
          <tr>
            <td><%= a.name %></td>
            <td class="text-right">
              <%= button_to "Remove", destroy_alias_admin_committee_path(@committee, alias_id: a.id),
                  method: :delete, class: "btn btn--sm btn--ghost text-danger",
                  form: { data: { turbo_confirm: "Remove this alias?" } } %>
            </td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% else %>
    <p class="text-secondary mb-4">No aliases.</p>
  <% end %>

  <%= form_with url: create_alias_admin_committee_path(@committee), local: true, class: "flex gap-2" do |f| %>
    <%= f.text_field :name, class: "form-input grow", placeholder: "e.g. Old Committee Name" %>
    <%= f.submit "Add Alias", class: "btn btn--secondary" %>
  <% end %>
</div>

<div class="card p-6 mb-6">
  <h2 class="text-lg font-bold mb-4">Members (<%= @memberships.count %>)</h2>
  <p class="text-sm text-secondary mb-4">Committee membership tracking. AI-driven extraction coming soon.</p>

  <% current = @memberships.select { |m| m.ended_on.nil? } %>
  <% past = @memberships.select { |m| m.ended_on.present? } %>

  <% if current.any? %>
    <h3 class="text-md font-bold mb-2">Current</h3>
    <table class="mb-4">
      <thead>
        <tr>
          <th>Member</th>
          <th>Role</th>
          <th>Since</th>
        </tr>
      </thead>
      <tbody>
        <% current.each do |m| %>
          <tr>
            <td><%= m.member.name %></td>
            <td><%= m.role&.humanize || "Member" %></td>
            <td><%= m.started_on %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>

  <% if past.any? %>
    <h3 class="text-md font-bold mb-2">Past</h3>
    <table>
      <thead>
        <tr>
          <th>Member</th>
          <th>Role</th>
          <th>Period</th>
        </tr>
      </thead>
      <tbody>
        <% past.each do |m| %>
          <tr>
            <td><%= m.member.name %></td>
            <td><%= m.role&.humanize || "Member" %></td>
            <td><%= m.started_on %> — <%= m.ended_on %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
  <% end %>

  <% if @memberships.empty? %>
    <p class="text-secondary">No members recorded yet.</p>
  <% end %>
</div>

<div class="card p-6">
  <h2 class="text-lg font-bold mb-4">Meetings (<%= @committee.meetings.count %>)</h2>
  <% recent_meetings = @committee.meetings.order(starts_at: :desc).limit(10) %>
  <% if recent_meetings.any? %>
    <table>
      <thead>
        <tr>
          <th>Date</th>
          <th>Body Name (Scraped)</th>
          <th>Status</th>
        </tr>
      </thead>
      <tbody>
        <% recent_meetings.each do |m| %>
          <tr>
            <td><%= link_to m.starts_at&.strftime("%b %d, %Y"), meeting_path(m) %></td>
            <td class="text-sm text-secondary"><%= m.body_name %></td>
            <td><%= m.status %></td>
          </tr>
        <% end %>
      </tbody>
    </table>
    <% if @committee.meetings.count > 10 %>
      <p class="text-sm text-muted mt-2">Showing 10 most recent of <%= @committee.meetings.count %> meetings.</p>
    <% end %>
  <% else %>
    <p class="text-secondary">No meetings linked yet.</p>
  <% end %>
</div>
```

**Step 5: Run controller tests**

Run: `bin/rails test test/controllers/admin/committees_controller_test.rb`

Expected: All tests pass.

**Step 6: Commit**

```bash
git add app/views/admin/committees/
git commit -m "$(cat <<'EOF'
feat: add admin committee views (index, show, new, edit, form)

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 12: Add committees to admin dashboard

**Files:**
- Modify: `app/views/admin/dashboard/show.html.erb`

**Step 1: Add committees link to the Content section**

In `app/views/admin/dashboard/show.html.erb`, add the following line to the Content section's `<ul>`, after the "Knowledgebase Sources" link:

```erb
<li><%= link_to "Committees & Boards", admin_committees_path %></li>
```

**Step 2: Verify manually or run existing dashboard test if one exists**

Run: `bin/rails test test/controllers/admin/`

Expected: All admin tests pass.

**Step 3: Commit**

```bash
git add app/views/admin/dashboard/show.html.erb
git commit -m "$(cat <<'EOF'
feat: add committees link to admin dashboard

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```

---

### Task 13: Run full test suite and CI checks

**Step 1: Run all tests**

Run: `bin/rails test`

Expected: All tests pass.

**Step 2: Run RuboCop**

Run: `bin/rubocop`

Expected: No new offenses. Fix any that arise.

**Step 3: Run CI**

Run: `bin/ci`

Expected: All checks pass (rubocop, bundler-audit, importmap audit, brakeman).

**Step 4: Fix any issues found**

If tests or linting fail, fix the issues and commit fixes.

---

### Task 14: Update documentation

**Files:**
- Modify: `CLAUDE.md` — add Committee model to Core Domain Models, update conventions
- Modify: `docs/DEVELOPMENT_PLAN.md` — add committees section if appropriate

**Step 1: Update CLAUDE.md**

Add `Committee` to the Core Domain Models section:

```
- **`Committee`** — Governing body (city board, tax-funded nonprofit, or external). Has `committee_type`, `status` (active/dormant/dissolved), `description` (injected into AI prompts). Linked to meetings, members via `CommitteeMembership`, and historical names via `CommitteeAlias`. Replaces free-form `body_name` for normalization while preserving `body_name` as historical display text.
```

Add committees to the AI prompt injection note in Conventions:

```
- **Committee context in AI prompts** — `OpenAiService#prepare_committee_context` injects active/dormant committee descriptions into analysis prompts. Managed via admin UI, not hardcoded.
```

**Step 2: Update design doc status**

Change the design doc status from "Draft" to "Implemented":

In `docs/plans/2026-02-28-committees-design.md`, change line 4 from `**Status**: Draft` to `**Status**: Implemented`.

**Step 3: Commit**

```bash
git add CLAUDE.md docs/plans/2026-02-28-committees-design.md
git commit -m "$(cat <<'EOF'
docs: document Committee model and AI prompt injection

Co-Authored-By: Claude Opus 4.6 <noreply@anthropic.com>
EOF
)"
```
