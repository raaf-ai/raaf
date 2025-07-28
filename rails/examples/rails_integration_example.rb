#!/usr/bin/env ruby
# frozen_string_literal: true

# This example demonstrates comprehensive Rails integration for Ruby AI Agents Factory Ruby.
# The library provides seamless Rails integration including automatic ActiveJob tracing,
# HTTP request correlation, a mountable engine for web-based monitoring, console helpers,
# and rake tasks for maintenance. This enables full-stack AI agent applications with
# proper observability and monitoring directly within Rails applications.

# NOTE: This example assumes you're running this in a Rails application context.
# Some features will only work within an actual Rails app environment.

require "raaf"

puts "=== Rails Integration Example ==="
puts "Rails detected: #{defined?(Rails) ? "Yes (#{Rails.version})" : 'No'}"
puts

# ============================================================================
# EXAMPLE 1: BASIC RAILS CONFIGURATION
# ============================================================================
# Configure Ruby AI Agents Factory for Rails with proper settings, middleware, and
# automatic tracing setup. This provides the foundation for all Rails-specific
# features.

puts "Example 1: Basic Rails Configuration"
puts "-" * 50

# This would typically go in config/initializers/raaf.rb
puts "Configuration for config/initializers/raaf.rb:"
puts <<~RUBY
  # Ruby AI Agents Factory configuration for Rails
  RAAF.configure do |config|
    # Basic configuration
    config.api_key = ENV['OPENAI_API_KEY']
    config.environment = Rails.env
    config.app_name = Rails.application.class.parent_name
  #{'  '}
    # Tracing configuration
    config.tracing.enabled = true
    config.tracing.sampling_rate = Rails.env.production? ? 0.1 : 1.0
    config.tracing.retention_days = 30
  #{'  '}
    # Logging configuration
    config.logging.level = Rails.env.production? ? :info : :debug
    config.logging.format = Rails.env.production? ? :json : :text
    config.logging.output = :rails  # Use Rails.logger
  end

  # Configure tracing engine
  RAAF::Tracing.configure do |config|
    config.auto_configure = true
    config.mount_path = "/admin/tracing"
    config.retention_days = 30
    config.sampling_rate = 1.0
  end

  # Add ActiveRecord processor for database storage
  RAAF.tracer.add_processor(
    RAAF::Tracing::ActiveRecordProcessor.new
  )

  # Add console processor for development
  if Rails.env.development?
    RAAF.tracer.add_processor(
      RAAF::Tracing::ConsoleProcessor.new
    )
  end
RUBY

puts "Rails configuration example provided"
puts

# ============================================================================
# EXAMPLE 2: RAILS ROUTES AND ENGINE MOUNTING
# ============================================================================
# Mount the tracing engine and configure routes for monitoring dashboard.

puts "Example 2: Rails Routes and Engine Mounting"
puts "-" * 50

puts "Configuration for config/routes.rb:"
puts <<~RUBY
  Rails.application.routes.draw do
    # Mount the tracing engine at /admin/tracing
    # This provides a complete web interface for viewing traces
    mount RAAF::Tracing::Engine => '/admin/tracing'
  #{'  '}
    # Optional: Add custom routes for API endpoints
    namespace :api do
      namespace :v1 do
        resources :ai_agents, only: [:create, :show] do
          member do
            get :traces
            get :performance
          end
        end
      end
    end
  #{'  '}
    # Optional: Add health check endpoint
    get '/health/agents', to: 'health#agents'
  end
RUBY

puts "Routes configuration example provided"
puts

# ============================================================================
# EXAMPLE 3: MIDDLEWARE INTEGRATION
# ============================================================================
# Add middleware for automatic request correlation and tracing context.

puts "Example 3: Middleware Integration"
puts "-" * 50

puts "Configuration for config/application.rb:"
puts <<~RUBY
  module YourApp
    class Application < Rails::Application
      # Add correlation middleware for request tracking
      config.middleware.use RAAF::Tracing::RailsIntegrations::CorrelationMiddleware
  #{'    '}
      # Configure Ruby AI Agents Factory tracing
      config.raaf_tracing.auto_configure = true
      config.raaf_tracing.mount_path = "/admin/tracing"
      config.raaf_tracing.retention_days = 30
      config.raaf_tracing.sampling_rate = 1.0
    end
  end
RUBY

puts "Middleware configuration example provided"
puts

# ============================================================================
# EXAMPLE 4: ACTIVE JOB INTEGRATION
# ============================================================================
# Automatic tracing for background jobs with proper context and metadata.

puts "Example 4: ActiveJob Integration"
puts "-" * 50

puts "Example ApplicationJob with automatic tracing:"
puts <<~RUBY
  class ApplicationJob < ActiveJob::Base
    # Include automatic tracing for all jobs
    include RAAF::Tracing::RailsIntegrations::JobTracing
  #{'  '}
    # Retry jobs with exponential backoff
    retry_on StandardError, wait: :exponentially_longer, attempts: 3
  #{'  '}
    # Discard jobs that consistently fail
    discard_on ActiveJob::DeserializationError
  end
RUBY

puts

puts "Example specific job with AI agent integration:"
puts <<~RUBY
  class ProcessUserQueryJob < ApplicationJob
    include RAAF::Logger
  #{'  '}
    # Job is automatically traced by JobTracing module
    def perform(user_id, query, context = {})
      log_info("Processing user query", user_id: user_id, query_length: query.length)
  #{'    '}
      # Create agent for this specific task
      agent = RAAF::Agent.new(
        name: "QueryProcessor",
        instructions: "Process user queries with helpful responses",
        model: "gpt-4o-mini"
      )
  #{'    '}
      # Create runner with tracing
      runner = RAAF::Runner.new(
        agent: agent,
        tracer: RAAF.tracer
      )
  #{'    '}
      # Add job context to trace metadata
      runner.tracer.current_trace&.metadata&.merge!(
        user_id: user_id,
        job_id: job_id,
        job_class: self.class.name,
        request_id: Thread.current[:raaf_request_id],
        context: context
      )
  #{'    '}
      # Process the query
      result = runner.run(query)
  #{'    '}
      # Store result (example)
      UserQueryResult.create!(
        user_id: user_id,
        query: query,
        response: result.messages.last[:content],
        trace_id: runner.tracer.current_trace&.trace_id,
        job_id: job_id
      )
  #{'    '}
      log_info("Query processed successfully", user_id: user_id,#{' '}
               trace_id: runner.tracer.current_trace&.trace_id)
  #{'    '}
      result
    rescue => e
      log_error("Query processing failed", user_id: user_id, error: e.message)
      raise
    end
  end
RUBY

puts "ActiveJob integration examples provided"
puts

# ============================================================================
# EXAMPLE 5: RAILS CONTROLLERS WITH TRACING
# ============================================================================
# Integrate AI agents into Rails controllers with proper tracing and context.

puts "Example 5: Rails Controllers with Tracing"
puts "-" * 50

puts "Example API controller with AI agent integration:"
puts <<~RUBY
  class Api::V1::ChatController < ApplicationController
    include RAAF::Logger
  #{'  '}
    before_action :authenticate_user!
    before_action :rate_limit_check
  #{'  '}
    # POST /api/v1/chat
    def create
      log_info("Chat request received", user_id: current_user.id,#{' '}
               message_length: chat_params[:message].length)
  #{'    '}
      # Create agent for this user's conversation
      agent = RAAF::Agent.new(
        name: "ChatAssistant",
        instructions: build_instructions_for_user(current_user),
        model: determine_model_for_user(current_user)
      )
  #{'    '}
      # Create runner with tracing
      runner = RAAF::Runner.new(
        agent: agent,
        tracer: RAAF.tracer
      )
  #{'    '}
      # Add request context to trace
      runner.tracer.current_trace&.metadata&.merge!(
        user_id: current_user.id,
        request_id: request.request_id,
        user_agent: request.user_agent,
        ip_address: request.remote_ip,
        endpoint: "#{request.method} #{request.path}",
        conversation_id: chat_params[:conversation_id]
      )
  #{'    '}
      # Build conversation context
      messages = build_conversation_context(chat_params[:conversation_id])
      messages << { role: "user", content: chat_params[:message] }
  #{'    '}
      # Process the chat
      result = runner.run(messages)
  #{'    '}
      # Save conversation
      conversation = save_conversation(
        user: current_user,
        conversation_id: chat_params[:conversation_id],
        messages: messages,
        response: result.messages.last[:content],
        trace_id: runner.tracer.current_trace&.trace_id
      )
  #{'    '}
      # Return response
      render json: {
        response: result.messages.last[:content],
        conversation_id: conversation.id,
        trace_id: runner.tracer.current_trace&.trace_id,
        model: agent.model,
        timestamp: Time.current.iso8601
      }
  #{'    '}
    rescue => e
      log_error("Chat processing failed", user_id: current_user.id,#{' '}
                error: e.message, error_class: e.class.name)
  #{'    '}
      render json: { error: "Processing failed" }, status: :internal_server_error
    end
  #{'  '}
    private
  #{'  '}
    def chat_params
      params.require(:chat).permit(:message, :conversation_id)
    end
  #{'  '}
    def build_instructions_for_user(user)
      base_instructions = "You are a helpful AI assistant."
  #{'    '}
      # Customize based on user preferences
      if user.preferences[:formal_tone]
        base_instructions += " Use a formal, professional tone."
      end
  #{'    '}
      if user.preferences[:expert_mode]
        base_instructions += " Provide detailed, technical explanations."
      end
  #{'    '}
      base_instructions
    end
  #{'  '}
    def determine_model_for_user(user)
      # Use different models based on user tier
      case user.tier
      when 'premium'
        'gpt-4o'
      when 'standard'
        'gpt-4o-mini'
      else
        'gpt-3.5-turbo'
      end
    end
  #{'  '}
    def build_conversation_context(conversation_id)
      return [] unless conversation_id
  #{'    '}
      Conversation.find_by(id: conversation_id)
                  &.messages
                  &.order(:created_at)
                  &.limit(20)
                  &.map { |msg| { role: msg.role, content: msg.content } } || []
    end
  #{'  '}
    def save_conversation(user:, conversation_id:, messages:, response:, trace_id:)
      conversation = Conversation.find_or_create_by(
        id: conversation_id,
        user: user
      )
  #{'    '}
      # Save the user message
      conversation.messages.create!(
        role: 'user',
        content: messages.last[:content],
        trace_id: trace_id
      )
  #{'    '}
      # Save the assistant response
      conversation.messages.create!(
        role: 'assistant',
        content: response,
        trace_id: trace_id
      )
  #{'    '}
      conversation
    end
  #{'  '}
    def rate_limit_check
      # Implement rate limiting logic
      return if rate_limit_ok?(current_user)
  #{'    '}
      render json: { error: "Rate limit exceeded" }, status: :too_many_requests
    end
  #{'  '}
    def rate_limit_ok?(user)
      # Simple rate limiting example
      key = "rate_limit:#{user.id}"
      current_count = Rails.cache.read(key) || 0
  #{'    '}
      if current_count >= user.rate_limit
        false
      else
        Rails.cache.write(key, current_count + 1, expires_in: 1.hour)
        true
      end
    end
  end
RUBY

puts "Rails controller integration example provided"
puts

# ============================================================================
# EXAMPLE 6: RAILS CONSOLE HELPERS
# ============================================================================
# Demonstrate console helpers for debugging and analysis.

puts "Example 6: Rails Console Helpers"
puts "-" * 50

puts "The following helpers are automatically available in Rails console:"
puts

# Mock the console helpers for demonstration
class MockConsoleHelpers
  include RAAF::Tracing::RailsIntegrations::ConsoleHelpers if defined?(RAAF::Tracing::RailsIntegrations::ConsoleHelpers)

  def demonstrate_helpers
    puts "Console helper methods:"
    puts "  recent_traces(limit: 10)     - Get recent traces"
    puts "  traces_for('workflow_name')  - Get traces for specific workflow"
    puts "  failed_traces(limit: 10)     - Get failed traces"
    puts "  slow_spans(threshold: 1000)  - Get slow spans (>1000ms)"
    puts "  error_spans(limit: 20)       - Get error spans"
    puts "  trace('trace_id')            - Get specific trace"
    puts "  span('span_id')              - Get specific span"
    puts "  trace_summary('trace_id')    - Print trace summary"
    puts "  performance_stats(timeframe: 24.hours) - Show performance stats"
    puts

    puts "Example usage in Rails console:"
    puts <<~CONSOLE
      # Get recent traces
      recent_traces

      # Find chat-related traces
      traces_for("ChatAssistant")

      # Find slow operations
      slow_spans(threshold: 5000)

      # Analyze specific trace
      trace_summary("abc123")

      # Show performance overview
      performance_stats(timeframe: 7.days)

      # Find errors in the last hour
      error_spans(limit: 50).where("created_at > ?", 1.hour.ago)
    CONSOLE
  end
end

console_demo = MockConsoleHelpers.new
console_demo.demonstrate_helpers
puts

# ============================================================================
# EXAMPLE 7: RAKE TASKS FOR MAINTENANCE
# ============================================================================
# Use built-in rake tasks for maintenance and analysis.

puts "Example 7: Rake Tasks for Maintenance"
puts "-" * 50

puts "Built-in rake tasks for Ruby AI Agents Factory:"
puts

# Demonstrate rake tasks
class MockRakeTasks
  def self.demonstrate_tasks
    puts "Available rake tasks:"
    puts "  raaf:tracing:cleanup     - Clean up old traces"
    puts "  raaf:tracing:report      - Generate performance report"
    puts "  raaf:tracing:stats       - Show database statistics"
    puts "  raaf:tracing:migrate     - Run tracing migrations"
    puts

    puts "Example task implementations:"
    puts

    puts "# lib/tasks/raaf.rake"
    puts <<~RAKE
      namespace :raaf do
        namespace :tracing do
          desc "Clean up old traces"
          task cleanup: :environment do
            older_than = ENV['OLDER_THAN']&.to_i&.days || 30.days
            count = RAAF::Tracing::RailsIntegrations::RakeTasks.cleanup_old_traces(older_than: older_than)
            puts "Cleaned up \#{count} traces older than \#{older_than.inspect}"
          end
      #{'    '}
          desc "Generate performance report"
          task report: :environment do
            timeframe = ENV['TIMEFRAME']&.to_i&.hours || 24.hours
            RAAF::Tracing::RailsIntegrations::RakeTasks.performance_report(timeframe: timeframe)
          end
      #{'    '}
          desc "Show database statistics"
          task stats: :environment do
            traces_count = RAAF::Tracing::Trace.count
            spans_count = RAAF::Tracing::Span.count
            avg_duration = RAAF::Tracing::Trace.average('duration_ms')
      #{'      '}
            puts "Database Statistics:"
            puts "  Traces: \#{traces_count}"
            puts "  Spans: \#{spans_count}"
            puts "  Average duration: \#{avg_duration&.round(2) || 'N/A'}ms"
          end
      #{'    '}
          desc "Run tracing migrations"
          task migrate: :environment do
            RAAF::Tracing::Engine.load_tasks
            Rake::Task['raaf_tracing:install:migrations'].invoke
            Rake::Task['db:migrate'].invoke
          end
        end
      end
    RAKE

    puts "Usage examples:"
    puts "  bundle exec rake raaf:tracing:cleanup"
    puts "  bundle exec rake raaf:tracing:report TIMEFRAME=168  # 7 days"
    puts "  bundle exec rake raaf:tracing:cleanup OLDER_THAN=7  # 7 days"
    puts "  bundle exec rake raaf:tracing:stats"
  end
end

MockRakeTasks.demonstrate_tasks
puts

# ============================================================================
# EXAMPLE 8: RAILS MODELS AND DATABASE INTEGRATION
# ============================================================================
# Show how to integrate with Rails models and database.

puts "Example 8: Rails Models and Database Integration"
puts "-" * 50

puts "Example Rails models with AI agent integration:"
puts

puts "User model with AI preferences:"
puts <<~RUBY
  class User < ApplicationRecord
    has_many :conversations, dependent: :destroy
    has_many :ai_interactions, dependent: :destroy
  #{'  '}
    # AI-specific attributes
    jsonb :ai_preferences, default: {}
  #{'  '}
    enum tier: { free: 0, standard: 1, premium: 2 }
  #{'  '}
    # Rate limiting
    def rate_limit
      case tier
      when 'premium' then 1000
      when 'standard' then 100
      else 50
      end
    end
  #{'  '}
    # Get AI agent configuration for this user
    def ai_agent_config
      {
        model: determine_model,
        instructions: build_instructions,
        tools: available_tools,
        max_tokens: token_limit
      }
    end
  #{'  '}
    private
  #{'  '}
    def determine_model
      case tier
      when 'premium' then 'gpt-4o'
      when 'standard' then 'gpt-4o-mini'
      else 'gpt-3.5-turbo'
      end
    end
  #{'  '}
    def build_instructions
      base = "You are a helpful AI assistant."
  #{'    '}
      if ai_preferences['formal_tone']
        base += " Use a formal, professional tone."
      end
  #{'    '}
      if ai_preferences['expert_mode']
        base += " Provide detailed, technical explanations."
      end
  #{'    '}
      base
    end
  #{'  '}
    def available_tools
      tools = ['web_search', 'calculator']
      tools << 'code_interpreter' if premium?
      tools << 'file_analysis' if standard? || premium?
      tools
    end
  #{'  '}
    def token_limit
      case tier
      when 'premium' then 4000
      when 'standard' then 2000
      else 1000
      end
    end
  end
RUBY

puts

puts "Conversation model with trace integration:"
puts <<~RUBY
  class Conversation < ApplicationRecord
    belongs_to :user
    has_many :messages, dependent: :destroy
  #{'  '}
    # Link to Ruby AI Agents Factory traces
    has_many :ai_interactions, dependent: :destroy
  #{'  '}
    validates :title, presence: true
  #{'  '}
    scope :recent, -> { order(updated_at: :desc) }
    scope :with_ai_traces, -> { joins(:ai_interactions).distinct }
  #{'  '}
    # Get related traces
    def traces
      return [] unless defined?(RAAF::Tracing::Trace)
  #{'    '}
      trace_ids = ai_interactions.pluck(:trace_id).compact
      RAAF::Tracing::Trace.where(trace_id: trace_ids)
    end
  #{'  '}
    # Performance metrics
    def performance_metrics
      traces_data = traces.includes(:spans)
  #{'    '}
      return {} if traces_data.empty?
  #{'    '}
      {
        total_interactions: traces_data.count,
        avg_response_time: traces_data.average('duration_ms'),
        success_rate: (traces_data.completed.count.to_f / traces_data.count) * 100,
        total_cost: calculate_total_cost(traces_data),
        error_count: traces_data.failed.count
      }
    end
  #{'  '}
    private
  #{'  '}
    def calculate_total_cost(traces_data)
      cost_manager = RAAF::Tracing::CostManager.new
  #{'    '}
      traces_data.sum do |trace|
        cost_manager.calculate_trace_cost(trace)[:total_cost]
      end
    end
  end
RUBY

puts

puts "AI Interaction model for tracking:"
puts <<~RUBY
  class AiInteraction < ApplicationRecord
    belongs_to :user
    belongs_to :conversation, optional: true
  #{'  '}
    validates :trace_id, presence: true, uniqueness: true
    validates :model, presence: true
  #{'  '}
    scope :recent, -> { order(created_at: :desc) }
    scope :by_model, ->(model) { where(model: model) }
    scope :successful, -> { where(status: 'completed') }
    scope :failed, -> { where(status: 'failed') }
  #{'  '}
    # Get the actual trace from Ruby AI Agents Factory
    def trace
      return nil unless defined?(RAAF::Tracing::Trace)
  #{'    '}
      RAAF::Tracing::Trace.find_by(trace_id: trace_id)
    end
  #{'  '}
    # Calculate cost for this interaction
    def cost
      return 0.0 unless trace
  #{'    '}
      cost_manager = RAAF::Tracing::CostManager.new
      cost_manager.calculate_trace_cost(trace)[:total_cost]
    end
  #{'  '}
    # Get performance data
    def performance_data
      return {} unless trace
  #{'    '}
      {
        duration_ms: trace.duration_ms,
        token_count: trace.spans.sum { |s| s.attributes&.dig('llm', 'usage', 'total_tokens') || 0 },
        model: model,
        status: status,
        error_count: trace.spans.errors.count
      }
    end
  end
RUBY

puts "Rails model integration examples provided"
puts

# ============================================================================
# EXAMPLE 9: RAILS GENERATORS AND SETUP
# ============================================================================
# Show how to use Rails generators for setup.

puts "Example 9: Rails Generators and Setup"
puts "-" * 50

puts "Rails generator for Ruby AI Agents Factory setup:"
puts

puts "Run the generator to set up Ruby AI Agents Factory in Rails:"
puts "  rails generate raaf:install"
puts

puts "This generator creates:"
puts "  config/initializers/raaf.rb     - Main configuration"
puts "  db/migrate/xxx_create_raaf_tracing.rb - Database migrations"
puts "  lib/tasks/raaf.rake             - Maintenance tasks"
puts "  app/models/concerns/ai_agent_integration.rb - Model concern"
puts

puts "Example generator implementation:"
puts <<~RUBY
  # lib/generators/raaf/install_generator.rb
  module OpenaiAgents
    module Generators
      class InstallGenerator < Rails::Generators::Base
        include Rails::Generators::Migration
  #{'      '}
        source_root File.expand_path('templates', __dir__)
  #{'      '}
        def self.next_migration_number(path)
          Time.current.utc.strftime("%Y%m%d%H%M%S")
        end
  #{'      '}
        def create_initializer
          copy_file 'initializer.rb', 'config/initializers/raaf.rb'
        end
  #{'      '}
        def create_migration
          migration_template 'migration.rb', 'db/migrate/create_raaf_tracing.rb'
        end
  #{'      '}
        def create_rake_tasks
          copy_file 'tasks.rake', 'lib/tasks/raaf.rake'
        end
  #{'      '}
        def create_concern
          copy_file 'ai_agent_integration.rb', 'app/models/concerns/ai_agent_integration.rb'
        end
  #{'      '}
        def mount_engine
          route "mount RAAF::Tracing::Engine => '/admin/tracing'"
        end
  #{'      '}
        def show_readme
          readme 'README'
        end
      end
    end
  end
RUBY

puts "Rails generator example provided"
puts

# ============================================================================
# EXAMPLE 10: PRODUCTION DEPLOYMENT CONSIDERATIONS
# ============================================================================
# Best practices for deploying Rails apps with Ruby AI Agents Factory.

puts "Example 10: Production Deployment Considerations"
puts "-" * 50

puts "Production deployment checklist:"
puts

puts "1. Environment Configuration:"
puts <<~CONFIG
  # config/environments/production.rb
  config.raaf_tracing.auto_configure = true
  config.raaf_tracing.sampling_rate = 0.1  # Sample 10% of requests
  config.raaf_tracing.retention_days = 30

  # Use background jobs for trace processing
  config.raaf_tracing.async_processing = true
  config.raaf_tracing.queue_name = 'tracing'
CONFIG

puts

puts "2. Database Configuration:"
puts <<~DATABASE
  # Use read replicas for tracing queries
  # config/database.yml
  production:
    primary:
      <<: *default
      database: myapp_production
    tracing:
      <<: *default
      database: myapp_tracing_production
      replica: true
DATABASE

puts

puts "3. Background Job Configuration:"
puts <<~JOBS
  # config/application.rb
  config.active_job.queue_adapter = :sidekiq

  # config/schedule.rb (whenever gem)
  every 1.day, at: '2:00 am' do
    rake 'raaf:tracing:cleanup'
  end

  every 1.week, at: '3:00 am' do
    rake 'raaf:tracing:report'
  end
JOBS

puts

puts "4. Monitoring and Alerting:"
puts <<~MONITORING
  # config/initializers/raaf.rb
  RAAF.tracer.add_processor(
    RAAF::Tracing::ActiveRecordProcessor.new
  )

  # Add custom monitoring
  RAAF.tracer.add_processor(
    RAAF::Tracing::DatadogProcessor.new
  )

  # Configure alerting
  alert_engine = RAAF::Tracing::AlertEngine.new
  alert_engine.add_alert_handler(
    RAAF::Tracing::AlertEngine::SlackHandler.new(
      ENV['SLACK_WEBHOOK_URL'],
      '#engineering-alerts'
    )
  )
MONITORING

puts

puts "5. Security Considerations:"
puts <<~SECURITY
  # Secure the tracing interface
  # config/routes.rb
  authenticate :user, ->(user) { user.admin? } do
    mount RAAF::Tracing::Engine => '/admin/tracing'
  end

  # Or use HTTP basic auth
  # config/initializers/raaf.rb
  RAAF::Tracing::Engine.middleware.use Rack::Auth::Basic do |username, password|
    username == ENV['TRACING_USERNAME'] && password == ENV['TRACING_PASSWORD']
  end
SECURITY

puts

puts "6. Performance Optimization:"
puts <<~PERFORMANCE
  # Use database connection pooling
  # config/database.yml
  production:
    pool: 25
  #{'  '}
  # Configure caching
  config.cache_store = :redis_cache_store, {
    url: ENV['REDIS_URL'],
    namespace: 'raaf',
    expires_in: 1.hour
  }

  # Use CDN for assets
  config.asset_host = ENV['CDN_HOST']
PERFORMANCE

puts "Production deployment considerations provided"
puts

# ============================================================================
# BEST PRACTICES SUMMARY
# ============================================================================

puts "\n=== Rails Integration Best Practices ==="
puts "=" * 50
puts <<~PRACTICES
  1. Configuration Management:
     - Use environment variables for sensitive configuration
     - Set different sampling rates for different environments
     - Configure proper log levels and formats
     - Use Rails.application.credentials for API keys

  2. Database Design:
     - Use separate database for tracing data if needed
     - Implement proper indexing for trace queries
     - Set up automatic cleanup of old traces
     - Consider read replicas for analytics queries

  3. Background Processing:
     - Use background jobs for expensive trace processing
     - Implement proper error handling and retries
     - Monitor background job queues
     - Use dedicated queues for tracing operations

  4. Performance Considerations:
     - Implement sampling in production environments
     - Use asynchronous trace processing
     - Cache expensive trace queries
     - Monitor database performance impact

  5. Security:
     - Secure the tracing web interface
     - Don't log sensitive information in traces
     - Use proper authentication and authorization
     - Implement rate limiting for tracing endpoints

  6. Monitoring and Alerting:
     - Set up alerts for high error rates
     - Monitor trace processing performance
     - Track cost and usage metrics
     - Implement health checks for tracing system

  7. Development Workflow:
     - Use console helpers for debugging
     - Implement proper test coverage
     - Use fixtures for trace data in tests
     - Set up development-friendly logging

  8. Production Deployment:
     - Use proper deployment strategies
     - Implement database migrations safely
     - Monitor application performance impact
     - Have rollback procedures ready
PRACTICES

puts "\nRails integration example completed!"
puts "This demonstrates comprehensive Rails integration for Ruby AI Agents Factory."
