#!/usr/bin/env ruby
# frozen_string_literal: true

##
# Basic Dashboard Example
#
# This example demonstrates how to set up a basic Rails application
# with RAAF dashboard integration.
#

require "bundler/inline"

gemfile do
  source "https://rubygems.org"
  gem "rails", "~> 7.0"
  gem "raaf-rails", path: ".."
  gem "raaf-core", path: "../../core"
  gem "raaf-memory", path: "../../memory"
  gem "raaf-tracing", path: "../../tracing"
end

require "rails"
require "action_controller/railtie"
require "raaf-rails"

##
# Minimal Rails application
#
class RAAFDashboardApp < Rails::Application
  config.root = __dir__
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = "secret"

  # Configure RAAF
  config.after_initialize do
    RAAF::Rails.configure do |config|
      config[:authentication_method] = :none
      config[:enable_dashboard] = true
      config[:enable_api] = true
      config[:dashboard_path] = "/dashboard"
    end
  end
end

# Initialize the Rails application
Rails.application.initialize!

# Define routes
Rails.application.routes.draw do
  mount RAAF::Rails::Engine, at: "/"

  root to: redirect("/dashboard")
end

# Custom controller
class ApplicationController < ActionController::Base
  include RAAF::Rails::Helpers::AgentHelper

  # Mock user for demo purposes
  class MockUser
    attr_reader :id, :name, :email

    def initialize(id:, name:, email:)
      @id = id
      @name = name
      @email = email
    end
  end

  def current_user
    MockUser.new(id: 1, name: "Demo User", email: "demo@example.com")
  end
end

# Run the application
if __FILE__ == $PROGRAM_NAME
  require "rack/handler/webrick"

  puts "=" * 60
  puts "RAAF Dashboard Example"
  puts "=" * 60
  puts
  puts "Starting server on http://localhost:3000"
  puts "Dashboard available at: http://localhost:3000/dashboard"
  puts "API available at: http://localhost:3000/api/v1"
  puts
  puts "Press Ctrl+C to stop the server"
  puts "=" * 60

  Rack::Handler::WEBrick.run Rails.application, Port: 3000
end
