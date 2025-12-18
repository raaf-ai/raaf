# frozen_string_literal: true

RAAF::Rails::Engine.routes.draw do
  root "dashboard#index"

  # Dashboard routes
  get "/dashboard", to: "dashboard#index"
  get "/dashboard/performance", to: "dashboard#performance"
  get "/dashboard/costs", to: "dashboard#costs"
  get "/dashboard/errors", to: "dashboard#errors"
  get "/dashboard/agents", to: "dashboard#agents"
  get "/dashboard/conversations", to: "dashboard#conversations"
  get "/dashboard/analytics", to: "dashboard#analytics"

  # Agent management routes
  resources :agents do
    member do
      get :chat
      post :test
      patch :deploy
      delete :undeploy
    end

    resources :conversations, only: %i[index show create]
  end

  # API routes
  namespace :api do
    namespace :v1 do
      resources :agents, only: %i[index show create update destroy] do
        member do
          post :chat
          get :status
          post :deploy
          delete :undeploy
        end

        resources :conversations, only: %i[index show create]
      end
    end
  end

  # Tracing routes
  namespace :tracing do
    resources :traces do
      collection do
        post :destroy_all
      end
      member do
        get :spans
        get :analytics
      end
    end

    resources :spans, only: [:index, :show] do
      member do
        post :evaluate
      end
      collection do
        get :tools
        get :flows
        post :destroy_all
      end

      # Span replay routes for debugging and experimentation
      resources :replays, only: [:index, :new, :create, :show]
    end

    get "timeline", to: "timeline#show"
    get "search", to: "search#index"

    # Cost management routes
    get "costs", to: "costs#index"
    get "costs/breakdown", to: "costs#breakdown"
    get "costs/trends", to: "costs#trends"
    get "costs/forecast", to: "costs#forecast"
    get "costs/optimization", to: "costs#optimization"
  end

  # Continuous evaluation routes
  namespace :continuous do
    # Evaluator discovery (read-only)
    resources :evaluators, only: [:index, :show]

    # Policy management with custom actions
    resources :policies do
      member do
        post :activate
        post :deactivate
        post :duplicate
      end
    end

    # Queue management
    resources :queue, only: [:index, :show] do
      member do
        post :retry
        post :cancel
      end
      collection do
        post :retry_failed
        delete :clear_completed
      end
    end

    # Results browsing
    resources :results, only: [:index, :show]

    # Analytics dashboard with data endpoints
    resource :analytics, only: [:show] do
      get :pass_rate_data
      get :score_distribution_data
      get :model_comparison_data
      get :failure_analysis_data
    end

    # System health monitoring
    resource :health, only: [:show], controller: 'health' do
      get :dashboard
    end
  end

  # WebSocket routes - Action Cable handles WebSocket connections
  # mount ActionCable.server => "/cable" if RAAF::Rails.config[:enable_websockets]
end