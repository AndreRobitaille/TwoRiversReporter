Rails.application.routes.draw do
  root "meetings#index"
  resources :meetings, only: %i[index show]
  resources :members, only: %i[index show]
  resources :topics, only: %i[index show]

  get "admin" => "admin/dashboard#show", as: :admin_root

  scope :admin do
    resource :session, only: %i[new create destroy], controller: "admin/sessions"
    resources :passwords, only: %i[new create edit update], param: :token, controller: "admin/passwords"
    resource :mfa_session, only: %i[new create], controller: "admin/mfa_sessions"
    resource :mfa_setup, only: %i[show create], controller: "admin/mfa_setup"
    resource :recovery_codes, only: %i[show create], controller: "admin/recovery_codes"
    resource :account_password, only: %i[edit update], controller: "admin/account_passwords"
    resources :users, only: %i[index new create], controller: "admin/users"

    resources :knowledge_sources, controller: "admin/knowledge_sources", as: :admin_knowledge_sources do
      post :reingest, on: :member
    end
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
