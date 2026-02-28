# Committee Membership Extraction — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extract committee membership from meeting minutes roll call sections, track per-meeting attendance, and auto-derive CommitteeMembership records.

**Architecture:** New `MeetingAttendance` model stores per-meeting presence data. `ExtractCommitteeMembersJob` uses gpt-5-mini to parse roll call text, creates attendance records, reconciles CommitteeMembership, and detects departures. Triggers alongside `ExtractVotesJob` in the existing pipeline.

**Tech Stack:** Rails 8.1, PostgreSQL, OpenAI gpt-5-mini, Minitest, Solid Queue

**Design doc:** `docs/plans/2026-02-28-committee-membership-extraction-design.md`

---

### Task 1: Create MeetingAttendance Migration and Model

**Files:**
- Create: `db/migrate/TIMESTAMP_create_meeting_attendances.rb`
- Create: `app/models/meeting_attendance.rb`
- Create: `test/models/meeting_attendance_test.rb`
- Modify: `app/models/meeting.rb` — add `has_many :meeting_attendances`
- Modify: `app/models/member.rb` — add `has_many :meeting_attendances`

**Step 1: Generate migration**

Run: `bin/rails generate migration CreateMeetingAttendances meeting:references member:references status:string attendee_type:string capacity:string`

Then edit the generated migration to match:

```ruby
class CreateMeetingAttendances < ActiveRecord::Migration[8.1]
  def change
    create_table :meeting_attendances do |t|
      t.references :meeting, null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.string :status, null: false
      t.string :attendee_type, null: false
      t.string :capacity

      t.timestamps
    end

    add_index :meeting_attendances, [:meeting_id, :member_id], unique: true
  end
end
```

**Step 2: Run migration**

Run: `bin/rails db:migrate`
Expected: Migration runs successfully, `meeting_attendances` table created.

**Step 3: Write the MeetingAttendance model**

```ruby
# app/models/meeting_attendance.rb
class MeetingAttendance < ApplicationRecord
  belongs_to :meeting
  belongs_to :member

  STATUSES = %w[present absent excused].freeze
  ATTENDEE_TYPES = %w[voting_member non_voting_staff guest].freeze

  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :attendee_type, presence: true, inclusion: { in: ATTENDEE_TYPES }

  scope :present, -> { where(status: "present") }
  scope :voting_members, -> { where(attendee_type: "voting_member") }
  scope :for_committee, ->(committee_id) {
    joins(:meeting).where(meetings: { committee_id: committee_id })
  }
end
```

**Step 4: Add associations to Meeting and Member**

In `app/models/meeting.rb`, add after the existing `has_many :motions` line:
```ruby
has_many :meeting_attendances, dependent: :destroy
```

In `app/models/member.rb`, add after `has_many :committee_memberships`:
```ruby
has_many :meeting_attendances, dependent: :destroy
```

**Step 5: Write model tests**

```ruby
# test/models/meeting_attendance_test.rb
require "test_helper"

class MeetingAttendanceTest < ActiveSupport::TestCase
  setup do
    @meeting = Meeting.create!(body_name: "City Council", starts_at: Time.current)
    @member = Member.create!(name: "Jane Doe")
  end

  test "valid attendance saves" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    assert attendance.save
  end

  test "status is required" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member, attendee_type: "voting_member"
    )
    assert_not attendance.valid?
  end

  test "status validates inclusion" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "unknown", attendee_type: "voting_member"
    )
    assert_not attendance.valid?
  end

  test "attendee_type is required" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member, status: "present"
    )
    assert_not attendance.valid?
  end

  test "attendee_type validates inclusion" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "spectator"
    )
    assert_not attendance.valid?
  end

  test "capacity is optional" do
    attendance = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "non_voting_staff",
      capacity: "City Manager"
    )
    assert attendance.valid?
  end

  test "unique constraint on meeting and member" do
    MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    duplicate = MeetingAttendance.new(
      meeting: @meeting, member: @member,
      status: "absent", attendee_type: "voting_member"
    )
    assert_not duplicate.save
  end

  test "present scope" do
    present = MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )
    absent = MeetingAttendance.create!(
      meeting: @meeting, member: Member.create!(name: "Other"),
      status: "absent", attendee_type: "voting_member"
    )

    assert_includes MeetingAttendance.present, present
    assert_not_includes MeetingAttendance.present, absent
  end

  test "for_committee scope filters by committee" do
    committee = Committee.create!(name: "Plan Commission")
    @meeting.update!(committee: committee)

    attendance = MeetingAttendance.create!(
      meeting: @meeting, member: @member,
      status: "present", attendee_type: "voting_member"
    )

    other_meeting = Meeting.create!(body_name: "Other", starts_at: Time.current)
    other = MeetingAttendance.create!(
      meeting: other_meeting, member: Member.create!(name: "Other"),
      status: "present", attendee_type: "voting_member"
    )

    results = MeetingAttendance.for_committee(committee.id)
    assert_includes results, attendance
    assert_not_includes results, other
  end
end
```

**Step 6: Run tests**

Run: `bin/rails test test/models/meeting_attendance_test.rb`
Expected: All tests pass.

**Step 7: Commit**

```bash
git add db/migrate/*_create_meeting_attendances.rb app/models/meeting_attendance.rb \
  app/models/meeting.rb app/models/member.rb test/models/meeting_attendance_test.rb \
  db/schema.rb
git commit -m "feat: add MeetingAttendance model for per-meeting roll call tracking"
```

---

### Task 2: Update CommitteeMembership ROLES Constant

**Files:**
- Modify: `app/models/committee_membership.rb:7` — update ROLES constant
- Modify: `test/models/committee_membership_test.rb` — add test for new roles

**Step 1: Write failing test**

Add to `test/models/committee_membership_test.rb`:
```ruby
test "staff role is valid" do
  membership = CommitteeMembership.new(committee: @committee, member: @member, role: "staff")
  assert membership.valid?
end

test "non_voting role is valid" do
  membership = CommitteeMembership.new(committee: @committee, member: @member, role: "non_voting")
  assert membership.valid?
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/committee_membership_test.rb -n "/staff role|non_voting role/"`
Expected: 2 failures — "staff" and "non_voting" not in ROLES.

**Step 3: Update ROLES constant**

In `app/models/committee_membership.rb`, change line 7 from:
```ruby
ROLES = %w[chair vice_chair member secretary alternate].freeze
```
to:
```ruby
ROLES = %w[chair vice_chair member secretary alternate staff non_voting].freeze
```

**Step 4: Run tests**

Run: `bin/rails test test/models/committee_membership_test.rb`
Expected: All pass.

**Step 5: Commit**

```bash
git add app/models/committee_membership.rb test/models/committee_membership_test.rb
git commit -m "feat: add staff and non_voting roles to CommitteeMembership"
```

---

### Task 3: Add `extract_committee_members` to OpenAiService

**Files:**
- Modify: `app/services/ai/open_ai_service.rb` — add new method after `extract_votes`
- Create: `test/services/ai/extract_committee_members_test.rb`

**Step 1: Write the test**

```ruby
# test/services/ai/extract_committee_members_test.rb
require "test_helper"
require "minitest/mock"

class Ai::ExtractCommitteeMembersTest < ActiveSupport::TestCase
  setup do
    @service = Ai::OpenAiService.new
  end

  test "extract_committee_members sends request and returns content" do
    minutes_text = <<~TEXT
      ROLL CALL
      Present: Smith, Johnson, Williams
      Absent: Davis
      Also Present: City Manager, Kyle Kordell
    TEXT

    mock_response = {
      "choices" => [{
        "message" => {
          "content" => {
            "voting_members_present" => ["Smith", "Johnson", "Williams"],
            "voting_members_absent" => ["Davis"],
            "non_voting_staff" => [{ "name" => "Kyle Kordell", "capacity" => "City Manager" }],
            "guests" => []
          }.to_json
        }
      }]
    }

    mock_client = Minitest::Mock.new
    mock_client.expect :chat, mock_response do |parameters:|
      parameters[:model] == Ai::OpenAiService::LIGHTWEIGHT_MODEL &&
        !parameters.key?(:temperature) &&
        parameters[:response_format] == { type: "json_object" }
    end

    @service.instance_variable_set(:@client, mock_client)

    result = @service.extract_committee_members(minutes_text)
    parsed = JSON.parse(result)

    assert_equal ["Smith", "Johnson", "Williams"], parsed["voting_members_present"]
    assert_equal ["Davis"], parsed["voting_members_absent"]
    assert_equal 1, parsed["non_voting_staff"].size
    assert_equal "Kyle Kordell", parsed["non_voting_staff"][0]["name"]
    mock_client.verify
  end

  test "extract_committee_members truncates long text" do
    long_text = "x" * 60_000

    captured_params = nil
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => '{"voting_members_present":[],"voting_members_absent":[],"non_voting_staff":[],"guests":[]}'
        }
      }]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) { captured_params = parameters; mock_response } do
      @service.extract_committee_members(long_text)
    end

    user_msg = captured_params[:messages].find { |m| m[:role] == "user" }[:content]
    assert user_msg.length < 55_000, "Prompt should truncate long text"
  end

  test "extract_committee_members prompt includes json keyword" do
    captured_params = nil
    mock_response = {
      "choices" => [{
        "message" => {
          "content" => '{"voting_members_present":[],"voting_members_absent":[],"non_voting_staff":[],"guests":[]}'
        }
      }]
    }

    client = @service.instance_variable_get(:@client)
    client.stub :chat, ->(parameters:) { captured_params = parameters; mock_response } do
      @service.extract_committee_members("ROLL CALL\nPresent: Smith")
    end

    all_text = captured_params[:messages].map { |m| m[:content] }.join(" ")
    assert_match(/json/i, all_text, "Prompt must contain 'json' for response_format")
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/ai/extract_committee_members_test.rb`
Expected: Failures — `extract_committee_members` method doesn't exist yet.

**Step 3: Implement the method**

Add to `app/services/ai/open_ai_service.rb` after the `extract_votes` method (after line 81):

```ruby
def extract_committee_members(text)
  prompt = <<~PROMPT
    <extraction_spec>
    Extract the roll call / attendance information from these meeting minutes into JSON.

    Meeting minutes use various formats for roll call. Common patterns:
    - "Present: Name1, Name2" / "Absent: Name3"
    - "Councilmembers: Name1, Name2" / "Absent and Excused: Name3"
    - "Also Present: Title, Name" (non-voting staff)
    - "Guests: Name" (visitors, not committee members)
    - Sometimes just a list of names with no labels (assume all present)

    Rules:
    - Committee/board members listed in the main roll call are voting members.
    - People listed under "Also Present", with government titles (Director, Manager,
      Chief, Clerk, Attorney, Secretary, Supervisor), or explicitly labeled as staff
      are non_voting_staff. Include their title/capacity.
    - People listed under "Guests" or "Visitors" are guests.
    - If someone has a title like "Recording Secretary" they are non_voting_staff.
    - Return full names as written. Do not abbreviate or alter names.
    - If no absent members are listed, return an empty array for voting_members_absent.

    Schema:
    {
      "voting_members_present": ["Full Name", ...],
      "voting_members_absent": ["Full Name", ...],
      "non_voting_staff": [{"name": "Full Name", "capacity": "Title"}, ...],
      "guests": [{"name": "Full Name"}]
    }
    </extraction_spec>

    Text:
    #{text.truncate(50000)}
  PROMPT

  response = @client.chat(
    parameters: {
      model: LIGHTWEIGHT_MODEL,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: "You are a data extraction assistant. Return only valid JSON." },
        { role: "user", content: prompt }
      ]
    }
  )
  response.dig("choices", 0, "message", "content")
end
```

**Important:** No `temperature` parameter — gpt-5-mini doesn't support it.

**Step 4: Run tests**

Run: `bin/rails test test/services/ai/extract_committee_members_test.rb`
Expected: All pass.

**Step 5: Run RuboCop**

Run: `bin/rubocop app/services/ai/open_ai_service.rb`
Expected: No offenses (or fix any that appear).

**Step 6: Commit**

```bash
git add app/services/ai/open_ai_service.rb test/services/ai/extract_committee_members_test.rb
git commit -m "feat: add extract_committee_members method to OpenAiService"
```

---

### Task 4: Build ExtractCommitteeMembersJob

**Files:**
- Create: `app/jobs/extract_committee_members_job.rb`
- Create: `test/jobs/extract_committee_members_job_test.rb`

This is the largest task. The job has 4 steps: AI extraction, attendance records, membership reconciliation, departure detection.

**Step 1: Write the test file**

```ruby
# test/jobs/extract_committee_members_job_test.rb
require "test_helper"
require "minitest/mock"

class ExtractCommitteeMembersJobTest < ActiveSupport::TestCase
  setup do
    @committee = Committee.create!(name: "City Council")
    @meeting = Meeting.create!(
      body_name: "City Council",
      starts_at: Time.zone.parse("2026-02-01 18:00"),
      committee: @committee
    )
    @doc = MeetingDocument.create!(
      meeting: @meeting,
      document_type: "minutes_pdf",
      extracted_text: "ROLL CALL\nPresent: Smith, Johnson\nAbsent: Davis\nAlso Present: City Manager, Kyle Kordell"
    )
  end

  def stub_ai_response(response_hash)
    mock_response = response_hash.to_json
    mock_service = Minitest::Mock.new
    mock_service.expect :extract_committee_members, mock_response do |text|
      text.is_a?(String)
    end
    mock_service
  end

  test "skips meeting without minutes text" do
    @doc.update!(extracted_text: nil)

    assert_no_difference "MeetingAttendance.count" do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end
  end

  test "creates MeetingAttendance records for all attendees" do
    ai_response = {
      "voting_members_present" => ["Smith", "Johnson"],
      "voting_members_absent" => ["Davis"],
      "non_voting_staff" => [{ "name" => "Kyle Kordell", "capacity" => "City Manager" }],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "MeetingAttendance.count", 4 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 2, @meeting.meeting_attendances.where(status: "present", attendee_type: "voting_member").count
    assert_equal 1, @meeting.meeting_attendances.where(status: "absent", attendee_type: "voting_member").count
    assert_equal 1, @meeting.meeting_attendances.where(attendee_type: "non_voting_staff").count

    staff = @meeting.meeting_attendances.find_by(attendee_type: "non_voting_staff")
    assert_equal "City Manager", staff.capacity
    mock_service.verify
  end

  test "creates Member records for new names" do
    ai_response = {
      "voting_members_present" => ["New Person"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "Member.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert Member.find_by(name: "New Person")
    mock_service.verify
  end

  test "normalizes member names by stripping titles" do
    ai_response = {
      "voting_members_present" => ["Councilmember Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    assert Member.find_by(name: "Smith")
    assert_nil Member.find_by(name: "Councilmember Smith")
    mock_service.verify
  end

  test "creates CommitteeMembership for new voting members" do
    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "CommitteeMembership.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    member = Member.find_by!(name: "Smith")
    membership = CommitteeMembership.find_by!(member: member, committee: @committee)
    assert_equal "member", membership.role
    assert_equal "ai_extracted", membership.source
    assert_equal @meeting.starts_at.to_date, membership.started_on
    assert_nil membership.ended_on
    mock_service.verify
  end

  test "creates CommitteeMembership with staff role for non-voting staff" do
    ai_response = {
      "voting_members_present" => [],
      "voting_members_absent" => [],
      "non_voting_staff" => [{ "name" => "Kyle Kordell", "capacity" => "City Manager" }],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_difference "CommitteeMembership.count", 1 do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    member = Member.find_by!(name: "Kyle Kordell")
    membership = CommitteeMembership.find_by!(member: member, committee: @committee)
    assert_equal "staff", membership.role
    assert_equal "ai_extracted", membership.source
    mock_service.verify
  end

  test "does not create membership for guests" do
    ai_response = {
      "voting_members_present" => [],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => [{ "name" => "Random Visitor" }]
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_no_difference "CommitteeMembership.count" do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    # But attendance record IS created
    assert_equal 1, @meeting.meeting_attendances.count
    mock_service.verify
  end

  test "does not overwrite admin_manual membership" do
    member = Member.create!(name: "Smith")
    existing = CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "chair", source: "admin_manual"
    )

    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_no_difference "CommitteeMembership.count" do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    existing.reload
    assert_equal "chair", existing.role
    assert_equal "admin_manual", existing.source
    mock_service.verify
  end

  test "does not duplicate existing ai_extracted membership" do
    member = Member.create!(name: "Smith")
    CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "ai_extracted"
    )

    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      assert_no_difference "CommitteeMembership.count" do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end
    mock_service.verify
  end

  test "is idempotent — destroys and recreates attendance on re-run" do
    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }

    # Run twice
    2.times do
      mock_service = stub_ai_response(ai_response)
      Ai::OpenAiService.stub :new, mock_service do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 1, @meeting.meeting_attendances.count
    assert_equal 1, CommitteeMembership.where(committee: @committee).count
  end

  test "skips membership reconciliation when meeting has no committee" do
    @meeting.update!(committee: nil)

    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      # Attendance records are still created
      assert_difference "MeetingAttendance.count", 1 do
        assert_no_difference "CommitteeMembership.count" do
          ExtractCommitteeMembersJob.perform_now(@meeting.id)
        end
      end
    end
    mock_service.verify
  end

  test "departure detection ends membership after 2 consecutive absences from roll call" do
    member = Member.create!(name: "Departed Person")
    membership = CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "ai_extracted",
      started_on: Date.new(2025, 1, 1)
    )

    # Create an older meeting where this member WAS present
    old_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2025-12-01 18:00")
    )
    MeetingDocument.create!(meeting: old_meeting, document_type: "minutes_pdf", extracted_text: "text")
    MeetingAttendance.create!(
      meeting: old_meeting, member: member,
      status: "present", attendee_type: "voting_member"
    )

    # Create a prior meeting where this member was NOT present
    prior_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2026-01-15 18:00")
    )
    MeetingDocument.create!(meeting: prior_meeting, document_type: "minutes_pdf", extracted_text: "text")
    # Note: No MeetingAttendance for Departed Person at prior_meeting

    # Now process current meeting (also missing this member)
    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    membership.reload
    assert_not_nil membership.ended_on
    assert_equal Date.new(2025, 12, 1), membership.ended_on  # Last meeting they attended
    mock_service.verify
  end

  test "departure detection does not end admin_manual membership" do
    member = Member.create!(name: "Admin Member")
    membership = CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "admin_manual"
    )

    # Two meetings without this member
    prior_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2026-01-15 18:00")
    )
    MeetingDocument.create!(meeting: prior_meeting, document_type: "minutes_pdf", extracted_text: "text")

    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => [],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    membership.reload
    assert_nil membership.ended_on
    mock_service.verify
  end

  test "departure detection does not end membership for member listed as absent" do
    member = Member.create!(name: "Absent But Still Member")
    CommitteeMembership.create!(
      committee: @committee, member: member,
      role: "member", source: "ai_extracted",
      started_on: Date.new(2025, 1, 1)
    )

    # Prior meeting — member was absent (but listed)
    prior_meeting = Meeting.create!(
      body_name: "City Council", committee: @committee,
      starts_at: Time.zone.parse("2026-01-15 18:00")
    )
    MeetingDocument.create!(meeting: prior_meeting, document_type: "minutes_pdf", extracted_text: "text")
    MeetingAttendance.create!(
      meeting: prior_meeting, member: member,
      status: "absent", attendee_type: "voting_member"
    )

    # Current meeting — member is absent again
    ai_response = {
      "voting_members_present" => ["Smith"],
      "voting_members_absent" => ["Absent But Still Member"],
      "non_voting_staff" => [],
      "guests" => []
    }
    mock_service = stub_ai_response(ai_response)

    Ai::OpenAiService.stub :new, mock_service do
      ExtractCommitteeMembersJob.perform_now(@meeting.id)
    end

    membership = CommitteeMembership.find_by!(member: member, committee: @committee, ended_on: nil)
    assert_not_nil membership  # Still active — they're absent, not departed
    mock_service.verify
  end

  test "handles JSON parse error gracefully" do
    mock_service = Minitest::Mock.new
    mock_service.expect :extract_committee_members, "not valid json" do |text|
      true
    end

    Ai::OpenAiService.stub :new, mock_service do
      assert_nothing_raised do
        ExtractCommitteeMembersJob.perform_now(@meeting.id)
      end
    end

    assert_equal 0, @meeting.meeting_attendances.count
    mock_service.verify
  end
end
```

**Step 2: Run tests to verify they fail**

Run: `bin/rails test test/jobs/extract_committee_members_job_test.rb`
Expected: All fail — job class doesn't exist yet.

**Step 3: Implement the job**

```ruby
# app/jobs/extract_committee_members_job.rb
class ExtractCommitteeMembersJob < ApplicationJob
  queue_as :default

  # Reuse the same title-stripping pattern from ExtractVotesJob
  TITLE_PATTERN = /^(Councilmember|Alderman|Alderperson|Commissioner|Manager|Clerk|Mr\.|Ms\.|Mrs\.)\s+/i

  def perform(meeting_id)
    meeting = Meeting.find(meeting_id)
    minutes_doc = meeting.meeting_documents.find_by(document_type: "minutes_pdf")

    unless minutes_doc&.extracted_text.present?
      Rails.logger.info "No minutes text available for Meeting #{meeting_id}"
      return
    end

    ai_service = ::Ai::OpenAiService.new
    json_response = ai_service.extract_committee_members(minutes_doc.extracted_text)

    begin
      data = JSON.parse(json_response)
    rescue JSON::ParserError => e
      Rails.logger.error "Failed to parse committee members JSON for Meeting #{meeting_id}: #{e.message}"
      return
    end

    # Step 2: Create MeetingAttendance records (idempotent)
    meeting.meeting_attendances.destroy_all
    create_attendance_records(meeting, data)

    # Step 3: Reconcile CommitteeMembership
    reconcile_memberships(meeting) if meeting.committee_id.present?

    # Step 4: Departure detection
    detect_departures(meeting) if meeting.committee_id.present?

    Rails.logger.info "Extracted #{meeting.meeting_attendances.count} attendees for Meeting #{meeting_id}"
  end

  private

  def normalize_name(raw_name)
    raw_name.gsub(TITLE_PATTERN, "").strip
  end

  def find_or_create_member(raw_name)
    name = normalize_name(raw_name)
    Member.find_or_create_by!(name: name)
  end

  def create_attendance_records(meeting, data)
    (data["voting_members_present"] || []).each do |name|
      next if name.blank?
      member = find_or_create_member(name)
      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "voting_member"
      )
    end

    (data["voting_members_absent"] || []).each do |name|
      next if name.blank?
      member = find_or_create_member(name)
      meeting.meeting_attendances.create!(
        member: member, status: "absent", attendee_type: "voting_member"
      )
    end

    (data["non_voting_staff"] || []).each do |entry|
      name = entry.is_a?(Hash) ? entry["name"] : entry
      next if name.blank?
      member = find_or_create_member(name)
      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "non_voting_staff",
        capacity: entry.is_a?(Hash) ? entry["capacity"] : nil
      )
    end

    (data["guests"] || []).each do |entry|
      name = entry.is_a?(Hash) ? entry["name"] : entry
      next if name.blank?
      member = find_or_create_member(name)
      meeting.meeting_attendances.create!(
        member: member, status: "present", attendee_type: "guest"
      )
    end
  end

  def reconcile_memberships(meeting)
    committee = meeting.committee

    meeting.meeting_attendances.where(attendee_type: %w[voting_member non_voting_staff]).find_each do |attendance|
      # Skip if any active membership already exists (regardless of source)
      next if CommitteeMembership.current.exists?(committee: committee, member_id: attendance.member_id)

      role = attendance.attendee_type == "voting_member" ? "member" : "staff"

      CommitteeMembership.create!(
        committee: committee,
        member_id: attendance.member_id,
        role: role,
        source: "ai_extracted",
        started_on: meeting.starts_at.to_date
      )
    end
  end

  def detect_departures(meeting)
    committee = meeting.committee

    # Find the 2 most recent meetings for this committee that have attendance records
    recent_meeting_ids = Meeting
      .where(committee: committee)
      .joins(:meeting_attendances)
      .where("meetings.starts_at <= ?", meeting.starts_at)
      .distinct
      .order(starts_at: :desc)
      .limit(2)
      .pluck(:id)

    # Need at least 2 meetings with attendance data to detect departures
    return if recent_meeting_ids.size < 2

    # Find active ai_extracted memberships for this committee
    active_memberships = CommitteeMembership
      .current
      .where(committee: committee, source: "ai_extracted")

    active_memberships.find_each do |membership|
      # Check if member appears in any of the 2 most recent meetings
      appears_in_recent = MeetingAttendance
        .where(meeting_id: recent_meeting_ids, member_id: membership.member_id)
        .exists?

      next if appears_in_recent

      # Member missing from both recent meetings — find their last attendance
      last_attendance = MeetingAttendance
        .joins(:meeting)
        .where(member_id: membership.member_id)
        .where(meetings: { committee_id: committee.id })
        .order("meetings.starts_at DESC")
        .first

      ended_date = last_attendance&.meeting&.starts_at&.to_date || meeting.starts_at.to_date
      membership.update!(ended_on: ended_date)
    end
  end
end
```

**Step 4: Run tests**

Run: `bin/rails test test/jobs/extract_committee_members_job_test.rb`
Expected: All pass.

**Step 5: Run RuboCop**

Run: `bin/rubocop app/jobs/extract_committee_members_job.rb`
Expected: No offenses (or fix any that appear).

**Step 6: Commit**

```bash
git add app/jobs/extract_committee_members_job.rb test/jobs/extract_committee_members_job_test.rb
git commit -m "feat: add ExtractCommitteeMembersJob for roll call extraction and membership reconciliation"
```

---

### Task 5: Wire Job into Pipeline (AnalyzePdfJob + OcrJob)

**Files:**
- Modify: `app/jobs/documents/analyze_pdf_job.rb:90-93` — add trigger
- Modify: `app/jobs/documents/ocr_job.rb:66-68` — add trigger

**Step 1: Add trigger to AnalyzePdfJob**

In `app/jobs/documents/analyze_pdf_job.rb`, after line 93 (`end` closing the ExtractVotesJob block), add:

```ruby
if document.document_type == "minutes_pdf"
  ExtractCommitteeMembersJob.perform_later(document.meeting_id)
end
```

Wait — `ExtractVotesJob` already has the same guard. To keep it DRY, combine with the existing block. Change lines 90-93 from:

```ruby
# Trigger Vote Extraction for minutes
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
end
```

to:

```ruby
# Trigger Vote and Membership Extraction for minutes
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
  ExtractCommitteeMembersJob.perform_later(document.meeting_id)
end
```

**Step 2: Add trigger to OcrJob**

In `app/jobs/documents/ocr_job.rb`, change lines 66-68 from:

```ruby
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
end
```

to:

```ruby
if document.document_type == "minutes_pdf"
  ExtractVotesJob.perform_later(document.meeting_id)
  ExtractCommitteeMembersJob.perform_later(document.meeting_id)
end
```

**Step 3: Run existing tests to make sure nothing breaks**

Run: `bin/rails test`
Expected: All existing tests pass. New triggers don't break anything because the jobs are enqueued asynchronously.

**Step 4: Run RuboCop on changed files**

Run: `bin/rubocop app/jobs/documents/analyze_pdf_job.rb app/jobs/documents/ocr_job.rb`
Expected: No offenses.

**Step 5: Commit**

```bash
git add app/jobs/documents/analyze_pdf_job.rb app/jobs/documents/ocr_job.rb
git commit -m "feat: trigger ExtractCommitteeMembersJob from minutes pipeline"
```

---

### Task 6: Create Rake Task for Backfill

**Files:**
- Create: `lib/tasks/members.rake`

**Step 1: Write the rake task**

```ruby
# lib/tasks/members.rake
namespace :members do
  desc "Extract committee memberships from the most recent minutes per committee"
  task extract_from_minutes: :environment do
    committees_processed = 0
    committees_skipped = 0

    Committee.find_each do |committee|
      meeting = committee.meetings
        .joins(:meeting_documents)
        .where(meeting_documents: { document_type: "minutes_pdf" })
        .where.not(meeting_documents: { extracted_text: [nil, ""] })
        .order(starts_at: :desc)
        .first

      unless meeting
        puts "#{committee.name}: no minutes found, skipping"
        committees_skipped += 1
        next
      end

      puts "#{committee.name}: processing #{meeting.body_name} (#{meeting.starts_at&.strftime('%Y-%m-%d')})"
      ExtractCommitteeMembersJob.perform_now(meeting.id)
      committees_processed += 1
    end

    puts "\nDone. Processed #{committees_processed} committees, skipped #{committees_skipped}."
  end
end
```

**Step 2: Verify it loads**

Run: `bin/rails -T members`
Expected: Shows `members:extract_from_minutes`.

**Step 3: Commit**

```bash
git add lib/tasks/members.rake
git commit -m "feat: add members:extract_from_minutes rake task for backfill"
```

---

### Task 7: Update Documentation

**Files:**
- Modify: `docs/DEVELOPMENT_PLAN.md` — add MeetingAttendance to core domain model, note in Committee section
- Modify: `CLAUDE.md` — add new job to job namespaces, add rake command

**Step 1: Update DEVELOPMENT_PLAN.md**

In the Core Domain Model section, after the CommitteeMembership paragraph (around line 149), add:

```markdown
- **MeetingAttendance** — Per-meeting roll call record. Tracks who was
  present, absent, or excused at each meeting, with attendee type
  (voting_member, non_voting_staff, guest) and optional capacity title.
  Created by `ExtractCommitteeMembersJob` from meeting minutes.
  Drives automatic `CommitteeMembership` creation and departure detection.
```

**Step 2: Update CLAUDE.md**

In the Commands table, add:
```
| Extract memberships from minutes | `bin/rails members:extract_from_minutes` |
```

In the Job Namespaces section, add to Top-level:
```
`ExtractCommitteeMembersJob`
```

In the Core Domain Models section, after CommitteeMembership bullet, add:
```
- **`MeetingAttendance`** — Per-meeting roll call record. Tracks present/absent/excused with attendee type (voting_member/non_voting_staff/guest). Created by `ExtractCommitteeMembersJob`. Drives automatic CommitteeMembership creation and departure detection (2 consecutive absences from roll call).
```

**Step 3: Commit**

```bash
git add docs/DEVELOPMENT_PLAN.md CLAUDE.md
git commit -m "docs: document MeetingAttendance model and membership extraction"
```

---

### Task 8: Run Full CI and Verify

**Step 1: Run full test suite**

Run: `bin/rails test`
Expected: All tests pass.

**Step 2: Run CI**

Run: `bin/ci`
Expected: Passes (rubocop, brakeman, bundler-audit, importmap audit).

**Step 3: Verify with a dry run (optional)**

If you want to test against real data before committing to backfill:

Run: `bin/rails runner "ExtractCommitteeMembersJob.perform_now(Meeting.joins(:meeting_documents).where(meeting_documents: { document_type: 'minutes_pdf' }).where.not(meeting_documents: { extracted_text: [nil, ''] }).order(starts_at: :desc).first.id)"`

This runs the job on a single recent meeting with minutes to verify the AI extraction works with real data.
