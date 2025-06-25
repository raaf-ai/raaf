# frozen_string_literal: true

OpenAIAgents::Tracing::Engine.routes.draw do
  root "traces#index"

  # Top-level tool calls and flow visualization routes
  get "tools", to: "spans#tools", as: :tools
  get "flows", to: "spans#flows", as: :flows

  resources :traces, only: %i[index show] do
    member do
      get :spans
      get :analytics
    end
    resources :spans, only: [:show], shallow: true
  end

  resources :spans, only: %i[index show] do
    member do
      get :events
    end
  end

  # Analytics and dashboard routes
  get "dashboard", to: "dashboard#index"
  get "dashboard/performance", to: "dashboard#performance"
  get "dashboard/costs", to: "dashboard#costs"
  get "dashboard/errors", to: "dashboard#errors"

  # API routes for real-time updates
  namespace :api do
    namespace :v1 do
      resources :traces, only: %i[index show] do
        resources :spans, only: %i[index show]
      end
      resources :spans, only: %i[index show]
      get "stats/performance", to: "stats#performance"
      get "stats/costs", to: "stats#costs"
      get "stats/errors", to: "stats#errors"
      get "live/traces", to: "live#traces"
    end
  end

  # Search endpoints
  get "search", to: "search#index"
  get "search/traces", to: "search#traces"
  get "search/spans", to: "search#spans"
end
