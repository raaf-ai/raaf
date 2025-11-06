# frozen_string_literal: true

Rails.application.routes.draw do
  # Mount the RAAF Eval UI engine
  mount RAAF::Eval::UI::Engine, at: "/eval"

  # Authentication routes
  get '/login', to: 'sessions#new'
  post '/login', to: 'sessions#create'
  delete '/logout', to: 'sessions#destroy'

  # Root route
  root to: redirect('/eval')

  # Health check
  get '/health', to: proc { [200, {}, ['OK']] }
end
