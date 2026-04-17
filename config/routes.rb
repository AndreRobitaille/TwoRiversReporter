Rails.application.routes.draw do
  root "home#index"
  get "about", to: "pages#about"
  # OG image source — dev/test only. The rake task (og:generate) renders
  # this ERB directly via ApplicationController.renderer, so the HTTP route
  # is only needed for visual preview in development.
  unless Rails.env.production?
    get "og/default", to: "og#default"
  end
  # NOTE: when adding a new public resource, update SitemapsController so the
  # new pages appear in /sitemap.xml. Internal nav links handle most crawler
  # discovery, but the sitemap is the explicit signal.
  resources :meetings, only: %i[index show]
  resources :committees, only: %i[index show], param: :slug
  get "members", to: redirect("/committees", status: 301), as: nil
  resources :members, only: %i[show]
  get "topics/explore", to: "topics#explore", as: :topics_explore
  resources :topics, only: %i[index show]

  get "sitemap.xml", to: "sitemaps#show", as: :sitemap, defaults: { format: :xml }

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
        get :repair, to: "admin/topic_repairs#show"
        get :history, to: "admin/topic_repairs#history"
        get :merge_candidates, to: "admin/topic_repairs#merge_candidates"
        get :impact_preview, to: "admin/topic_repairs#impact_preview"
        post :merge_from_repair, to: "admin/topic_repairs#merge"
        post :merge_away_from_repair, to: "admin/topic_repairs#merge_away"
        post :topic_to_alias, to: "admin/topic_repairs#topic_to_alias"
        post :flip_alias, to: "admin/topic_repairs#flip_alias"
        post :move_alias, to: "admin/topic_repairs#move_alias"
        patch :update_alias, to: "admin/topic_repairs#update_alias"
        post :promote_alias, to: "admin/topic_repairs#promote_alias"
        delete :remove_alias, to: "admin/topic_repairs#remove_alias"
        post :promote_alias, to: "admin/topic_repairs#promote_alias"
        post :retire, to: "admin/topic_repairs#retire"
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

    resources :committees, controller: "admin/committees", as: :admin_committees do
      member do
        post :create_alias
        delete :destroy_alias
      end
    end

    resources :members, only: %i[index show], controller: "admin/members", as: :admin_members do
      member do
        post :create_alias
        delete :destroy_alias
        post :merge
      end
    end

    resources :prompt_templates, controller: "admin/prompt_templates", as: :admin_prompt_templates, only: [ :index, :edit, :update ] do
      member do
        get :diff
        post :test_run
      end
    end

    resources :job_runs, controller: "admin/job_runs", as: :admin_job_runs, only: [ :index, :create ] do
      collection do
        get :count
      end
    end

    get "search", to: "admin/searches#index", as: :admin_search
  end

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  get "up" => "rails/health#show", as: :rails_health_check
end
