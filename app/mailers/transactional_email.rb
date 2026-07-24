class TransactionalEmail < ApplicationMailer
  def magic_link(email_address, raw_token)
    mail(
      to: email_address,
      subject: "Your sign-in link",
      body: "Your sign-in link token is #{raw_token}."
    )
  end
end
