class TransactionalEmail < ApplicationMailer
  def magic_link(user, magic_link)
    @magic_link = magic_link
    mail to: user.email_address, subject: "Your sign-in link"
  end
end
