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

  def self.normalize(email_address)
    email_address.to_s.strip.downcase
  end
end
