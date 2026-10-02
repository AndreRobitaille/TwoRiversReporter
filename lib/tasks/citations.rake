namespace :citations do
  desc "Dry-run a bounded citation-only repair (SUMMARY_ID, PROMPT_RUN_ID, DOCUMENT_ID; APPLY=true to write)"
  task repair_summary: :environment do
    ids = %w[SUMMARY_ID PROMPT_RUN_ID DOCUMENT_ID].to_h do |key|
      value = ENV.fetch(key)
      abort "#{key} must be a positive integer" unless value.match?(/\A[1-9]\d*\z/)
      [ key.downcase.to_sym, value.to_i ]
    end
    apply = ENV["APPLY"] == "true"
    expected = if apply
      %w[input_sha256 protected_sha256 source_version].to_h do |key|
        value = ENV.fetch("EXPECTED_#{key.upcase}")
        abort "EXPECTED_#{key.upcase} must be a SHA-256 from the dry run" unless value.match?(/\A[0-9a-f]{64}\z/)
        [ key.to_sym, value ]
      end
    else
      {}
    end
    result = Citations::SummaryRepair.new(**ids).call(apply: apply, expected: expected)
    puts JSON.pretty_generate(result)
  end
end
