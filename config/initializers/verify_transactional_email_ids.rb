# Refuse to boot a production container that is missing a Loops transactional
# id. Failing here means Kamal's healthcheck fails and the deploy rolls back,
# so a misconfiguration never reaches a user as a 500 (see the enumeration note
# on TransactionalEmail.verify_transactional_ids!).
#
# Skipped during `assets:precompile` in the Docker build, which runs with
# RAILS_ENV=production and SECRET_KEY_BASE_DUMMY=1 but none of the real env.
Rails.application.config.after_initialize do
  next if ENV["SECRET_KEY_BASE_DUMMY"].present?

  TransactionalEmail.verify_transactional_ids!
end
