# frozen_string_literal: true

RAAF::Rails::Engine.routes.draw do
  root "dashboard#index"

  # The console's stylesheet and controllers, each at a path carrying its own
  # content hash so it can be cached for a year. See RAAF::Rails::AssetsController.
  get "/assets/console-:digest.css",
      to: "assets#stylesheet", as: :console_stylesheet,
      constraints: { digest: /[0-9a-f]{16}/ }, format: false

  get "/assets/console-:digest.js",
      to: "assets#javascript", as: :console_javascript,
      constraints: { digest: /[0-9a-f]{16}/ }, format: false

  # Dashboard routes
  get "/dashboard", to: "dashboard#index"
  get "/dashboard/performance", to: "dashboard#performance"
  get "/dashboard/costs", to: "dashboard#costs"
  get "/dashboard/errors", to: "dashboard#errors"
  get "/dashboard/agents", to: "dashboard#agents"

  # No agent-management or conversation screens. The five that were routed
  # here -- /agents index, show, new, edit and chat, plus
  # /dashboard/conversations and /dashboard/analytics -- rendered
  # SimpleDashboard: a standalone HTML document with its own four-link nav and
  # its own inline stylesheet, outside the console shell entirely. A reader who
  # followed one lost the sidebar and landed somewhere that looked like a
  # different application, and there was no feature behind any of them: the
  # writes redirected to the stubs and the JSON members answered a fixed
  # {status: "ok"}.
  #
  # The JSON API under /api/v1 went the same way, for the same reason and one
  # more: it persisted nothing, read nothing, and answered 200 to every call,
  # so anything integrating against it got plausible-looking silence instead of
  # an error. There are no agent records in the engine for it to serve. A
  # consumer meeting a 404 learns something true.

  # The living component library — every Glass Morph component as the
  # dashboard renders it. Useful when changing a component, and as the
  # reference for which component to reach for.
  get "/style_guide", to: "style_guide#show", as: :style_guide

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

    # Every replay, across every span. The span-scoped list below is the same
    # screen filtered to one span; this is the console's entry to it, since a
    # replay is worth finding again without first finding the span it came
    # from.
    resources :replays, only: [:index]

    # No `show`: a span is read in its trace, with itself selected. The
    # member and nested routes below still take a span id -- evaluating a span
    # and replaying one are things done to a span, not a screen showing it.
    resources :spans, only: %i[index] do
      member do
        post :evaluate
      end
      collection do
        get :tools
        get :flows
        post :destroy_all
      end

      # Span replay routes for debugging and experimentation
      resources :replays, only: %i[index new create show]
    end

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
    resources :evaluators, only: %i[index show]

    # Policy management with custom actions
    resources :policies do
      member do
        post :activate
        post :deactivate
        post :duplicate
      end
    end

    # Queue management
    resources :queue, only: %i[index show] do
      member do
        post :retry
        post :cancel
      end
      collection do
        post :retry_failed
        delete :discard_failed
      end
    end

    # Results browsing
    resources :results, only: %i[index show]

    # Every evaluator's score against every bucket in the window.
    get "trends", to: "trends#index", as: :trends

    # Analytics dashboard with data endpoints
    resource :analytics, only: [:show] do
      get :pass_rate_data
      get :score_distribution_data
      get :model_comparison_data
      get :failure_analysis_data
    end

    # System health monitoring
    resource :health, only: [:show], controller: "health" do
      get :dashboard
    end
  end

  # Opik-inspired features: Datasets, Experiments, Feedback Scores, Prompts
  namespace :eval do
    resources :datasets do
      member do
        post :new_version
        post :archive
      end
      resources :items, controller: "dataset_items", only: %i[index show create destroy] do
        collection do
          post :import_from_span
        end
      end
    end

    resources :experiments do
      member do
        post :run
        post :cancel
        get :compare
      end
      resources :results, controller: "experiment_results", only: %i[index show]
    end

    resources :feedback_scores, only: %i[index show create destroy] do
      collection do
        post :score_span
        post :score_trace
        # JSON only: the HTML screen behind this repeated the Feedback list's
        # own figures, and nothing linked it.
        get :statistics, defaults: { format: :json }
      end
    end

    resources :feedback_score_definitions, only: %i[index show create update destroy]

    resources :prompts do
      resources :versions, controller: "prompt_versions", only: %i[index show new create] do
        member do
          post :publish
          post :archive
        end
      end
      member do
        get :diff
        get :history
      end
    end
  end

  # WebSocket routes - Action Cable handles WebSocket connections
  # mount ActionCable.server => "/cable" if RAAF::Rails.config[:enable_websockets]
end
