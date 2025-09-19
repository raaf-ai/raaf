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
      member do
        get :spans
        get :analytics
      end
    end
    
    resources :spans, only: [:index, :show] do
      collection do
        get :tools
        get :flows
      end
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

  # WebSocket routes - Action Cable handles WebSocket connections
  # mount ActionCable.server => "/cable" if RAAF::Rails.config[:enable_websockets]
end