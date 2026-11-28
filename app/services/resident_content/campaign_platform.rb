module ResidentContent
  # Select from one member's campaign sources for one election, before reading
  # any council activity. Keep older, unclassified material available separately.
  class CampaignPlatform
    EDITION = YAML.safe_load_file(Rails.root.join("config/campaign_platform_2024.yml")).freeze
    EVIDENCE_FIELDS = %w[source_name question kind summary supporting_quote conditions timeframe].freeze

    attr_reader :items, :unreviewed, :statements, :selection_review

    def self.by_election(statements)
      statements.group_by { |row| row.campaign_source_version.election_on }.transform_values { |rows| new(rows) }
    end

    def self.source_digest(records)
      evidence = records.sort_by(&:sequence).map { |row| [ row.sequence, *row.data.values_at(*EVIDENCE_FIELDS) ] }
      Digest::SHA256.hexdigest(evidence.to_json)
    end

    # Tie status refinements and vote details to the exact saved finding and its citations.
    def self.reviewed_findings(report, name)
      rows = report.promise_assessments
      edition_on = Date.iso8601(EDITION.fetch("election"))
      return rows unless report.term_started_on == edition_on + 14

      items = EDITION.fetch("members").dig(name, "items") || []
      rows.map do |row|
        headings = row["heading"].to_s.split(" / ")
        notes = items.select { |item| headings.include?(item.fetch("heading")) }.flat_map { |item| item.fetch("reports", []) }
        note = notes.find { |entry| entry.fetch("text") == row.fetch("reason") }
        next row unless note

        cited = row.fetch("sources").pluck("url")
        urls = note.fetch("sources").map { |key| EDITION.fetch("council_sources").fetch(key).fetch("url") }
        next row unless (urls - cited).empty?

        row = row.merge(note.slice("profile_excerpt", "profile_subject", "finding_detail"))
        row["status"] = note.fetch("finding_status") if note["finding_status"]
        row.fetch("status") == "met" ? row.merge(note.slice("roll_call")) : row
      end
    end

    def initialize(records, edition: EDITION, include_council_records: true, reviewed_only: false)
      @unreviewed = []
      @record_sources = CampaignRecordSources.new(edition.fetch("council_sources", {})) if include_council_records
      selection = Campaigns::PlatformSelection.new(records)
      @selection_review = selection.published
      consolidated = @selection_review ? selection.items(@selection_review) : []
      # While a first cross-source check is queued, do not promote unreviewed
      # headings to the public promise list. Older extractions still have their
      # original source-level classification until reconciliation prepares them.
      under_review = reviewed_only || @selection_review || selection.current || selection.rows.any? { |row| row.data["action_quote"] }
      records_to_extract = under_review ? records - selection.rows : records
      extracted = []
      editorial = records_to_extract.group_by { |row| row.data["source_name"] }.flat_map do |name, statements|
        review = edition.fetch("members")[name]
        references = {}
        statements.group_by(&:campaign_source_version).each do |source, rows|
          key = edition.fetch("sources").key(source.source_url)
          if key && review && source.election_on.iso8601 == edition.fetch("election") && review.fetch("digests").key?(key)
            if review.fetch("digests")[key] == self.class.source_digest(rows)
              rows.each { |row| references["#{key}.#{row.sequence}"] = row }
            else
              # A changed edition cannot revive statements the source review
              # removed. Use current extracted headings for retained references.
              retained = review.fetch("items").flat_map { |item| item.fetch("refs") }
              extracted.concat(rows.filter_map { |row| extracted_item(row) if retained.include?("#{key}.#{row.sequence}") && row.data["comparison_heading"].present? })
            end
          else
            extracted.concat(rows.filter_map { |row| extracted_item(row) })
          end
        end
        references.empty? ? [] : reviewed_items(review.fetch("items"), references)
      end
      @unreviewed.uniq!
      groups = (editorial + consolidated + extracted).group_by do |item|
        [ item[:kind], item[:heading].squish.downcase, Array(item[:qualifications]).compact_blank ]
      end
      @items = groups.values.map do |group|
        group.first.merge(statements: group.flat_map { |item| item[:statements] }.uniq,
          comparable: group.flat_map { |item| item[:comparable] }.uniq)
      end
      visible = (@items.flat_map { |item| item.fetch(:statements) } + @unreviewed).to_set
      @statements = records.select { |row| visible.include?(row) }
    end

    private

    def reviewed_items(items, references)
      items.filter_map do |item|
        refs = item.fetch("refs")
        mentions = refs.filter_map { |ref| references[ref] }
        # If the primary source changes, its editorial wording loses its basis.
        unless references.key?(refs.first)
          @unreviewed.concat(mentions)
          next
        end
        { heading: item.fetch("heading"), kind: item.fetch("kind"), description: item.fetch("description"),
          statements: mentions, comparable: item.fetch("compare", refs).filter_map { |ref| references[ref] },
          reviewed_action: item["reviewed_action"], comparison_topic: item["comparison_topic"], prior_review_terms: item["prior_review_terms"] }
          .merge(@record_sources ? @record_sources.review(item) : {})
      end
    end

    def extracted_item(row)
      unless row.data.key?("comparison_heading")
        @unreviewed << row
        return
      end
      heading = row.data["comparison_heading"]
      kind = row.data.fetch("kind")
      return if heading.blank? || kind == "retrospective_claim"

      { heading: heading, kind: CampaignStatement::KINDS.fetch(kind), description: row.data.fetch("summary"),
        qualifications: row.data.values_at("conditions", "timeframe"), statements: [ row ], comparable: [ row ] }
    end
  end
end
