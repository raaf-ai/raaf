# frozen_string_literal: true

Rails.application.routes.draw do
  # "/raaf" is the mount point the engine documents and the one its components
  # build links against by hand (see Tracing::BaseComponent), so a page rendered
  # here links to the same URLs a spec asks for.
  mount RAAF::Rails::Engine, at: "/raaf", as: "raaf_rails"
end
