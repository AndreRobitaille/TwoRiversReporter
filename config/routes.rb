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

    resource :summaries, only: [ :show ], controller: "admin/summaries", as: :admin_summaries do
      post :regenerate_all, on: :collection
      post :regenerate_one, on: :collection
    end

    resource :jobs, only: [ :show ], controller: "admin/jobs", as: :admin_jobs do
      post :retry_failed, on: :member
      post :retry_all_failed, on: :collection
      delete :discard_failed, on: :member
      post :clear_completed, on: :collection
    end

    resources :topics, controller: "admin/topics", as: :admin_topics do
      collection do
        get :search
        post :bulk_update
      end
      member do
        post :approve
        post :block
        post :unblock
        post :needs_review
        post :pin
        post :unpin
        post :merge
        post :create_alias
      end
    end

    resources :topic_blocklists, controller: "admin/topic_blocklists", as: :admin_topic_blocklists
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
