# frozen_string_literal: true

RAAF::Eval::UI::Engine.routes.draw do
  # Spans resources (browsing and selection)
  resources :spans, only: %i[index show] do
    collection do
      get :search
      get :filter
    end
  end

  # Evaluations resources (execution and results)
  resources :evaluations, only: %i[new create show destroy] do
    member do
      post :execute
      get :status
      get :results
    end
  end

  # Sessions resources (saved evaluations)
  resources :sessions, only: %i[index show create update destroy]

  # Root route
  root to: "spans#index"
end
