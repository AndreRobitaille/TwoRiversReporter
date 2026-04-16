class AdminMfaPolicy
  def self.enforced?
    !Rails.env.development?
  end
end
