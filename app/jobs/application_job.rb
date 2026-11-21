class ApplicationJob < ActiveJob::Base
  # A historical batch drives its named stages inline. Ordinary queued
  # follow-ups would escape both the meeting scope and the one-time ledger.
  before_enqueue { throw :abort if CouncilHistory::Execution.meeting_id }

  # Automatically retry jobs that encountered a deadlock
  retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  discard_on ActiveJob::DeserializationError

  # Retry on transient OpenAI/network failures with backoff
  retry_on Faraday::Error, wait: :polynomially_longer, attempts: 3
  retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 3
  retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 3
end
