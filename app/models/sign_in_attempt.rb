# app/models/sign_in_attempt.rb
class SignInAttempt < ApplicationRecord
  WINDOW = 15.minutes

  def self.throttled?(email_address)
    where(email_address: normalize(email_address))
      .where(created_at: WINDOW.ago..)
      .exists?
  end

  def self.record!(email_address)
    create!(email_address: normalize(email_address))
  end

  # Undo the throttle for an address whose attempt could not actually be
  # delivered. Without this a transient mail-provider outage locks a real person
  # out for the full window, and their retry is answered with the success notice
  # while no email is sent.
  def self.release!(email_address)
    where(email_address: normalize(email_address))
      .where(created_at: WINDOW.ago..)
      .delete_all
  end

  def self.normalize(email_address)
    email_address.to_s.strip.downcase
  end
end
