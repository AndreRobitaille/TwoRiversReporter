module Admin
  # The single source of truth for admin navigation.
  #
  # Both the sidebar (app/views/admin/shared/_sidebar.html.erb) and the
  # dashboard launcher (app/views/admin/dashboard/show.html.erb) render from
  # this constant. They previously drifted into two different, disagreeing
  # lists; rendering both from one structure makes that impossible rather
  # than merely discouraged.
  #
  # Surfaces reached in context are deliberately absent: generated images
  # (from a topic or meeting), membership applications (from a user), and
  # personal security settings (the sidebar's user menu).
  class Navigation
    Item = Data.define(:label, :path_helper, :controller, :description)
    Group = Data.define(:title, :items)

    GROUPS = [
      Group.new(
        title: "Topics",
        items: [
          Item.new(label: "All Topics", path_helper: :admin_topics_path, controller: "topics",
                   description: "Review, triage, and combine civic topics."),
          Item.new(label: "Blocklist", path_helper: :admin_topic_blocklists_path, controller: "topic_blocklists",
                   description: "Names that may never become topics.")
        ].freeze
      ),
      Group.new(
        title: "Meetings",
        items: [
          Item.new(label: "Meetings", path_helper: :admin_meetings_path, controller: "meetings",
                   description: "Find a meeting and manage its generated image."),
          Item.new(label: "Add Transcript", path_helper: :admin_transcript_imports_path, controller: "transcript_imports",
                   description: "Import YouTube captions or upload an SRT file."),
          Item.new(label: "Summaries", path_helper: :admin_summaries_path, controller: "summaries",
                   description: "Summary coverage and bulk regeneration.")
        ].freeze
      ),
      Group.new(
        title: "The Record",
        items: [
          Item.new(label: "Committees", path_helper: :admin_committees_path, controller: "committees",
                   description: "Governing bodies and the descriptions the AI reads."),
          Item.new(label: "Members", path_helper: :admin_members_path, controller: "members",
                   description: "Officials, aliases, votes, and attendance."),
          Item.new(label: "Knowledge Sources", path_helper: :admin_knowledge_sources_path, controller: "knowledge_sources",
                   description: "Background context retrieved during summarization."),
          Item.new(label: "Knowledge Search", path_helper: :admin_search_path, controller: "searches",
                   description: "Query the knowledge base and meeting documents.")
        ].freeze
      ),
      Group.new(
        title: "The Machine",
        items: [
          Item.new(label: "Run a Job", path_helper: :admin_job_runs_path, controller: "job_runs",
                   description: "Pick a job and targets, then enqueue."),
          Item.new(label: "Queue & Failures", path_helper: :admin_jobs_path, controller: "jobs",
                   description: "Worker status, pending work, and failed jobs."),
          Item.new(label: "Prompts", path_helper: :admin_prompt_templates_path, controller: "prompt_templates",
                   description: "The AI prompt text, with version history.")
        ].freeze
      ),
      Group.new(
        title: "Site",
        items: [
          Item.new(label: "Access Mode", path_helper: :admin_site_settings_path, controller: "site_settings",
                   description: "Whether anonymous visitors see everything or a teaser."),
          Item.new(label: "Redirects", path_helper: :admin_redirects_path, controller: "redirects",
                   description: "Permanent redirects for moved URLs."),
          # "User Accounts", not "Admin Users": this page lists every account,
          # and its per-user controls (approve, reject, disable, revoke
          # sessions, delete) apply to ordinary members as much as to admins.
          # The old label read as admin-only and hid the ordinary-member
          # administration that was there all along. "User" distinguishes it
          # from The Record's "Members", which are city officials, not accounts.
          Item.new(label: "User Accounts", path_helper: :users_path, controller: "users",
                   description: "Accounts, applications, sessions, and passkeys."),
          Item.new(label: "Audit Log", path_helper: :admin_audit_events_path, controller: "audit_events",
                   description: "Destructive and privilege-changing actions.")
        ].freeze
      )
    ].freeze

    def self.items
      GROUPS.flat_map(&:items)
    end
  end
end
