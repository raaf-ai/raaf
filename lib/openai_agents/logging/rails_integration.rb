# frozen_string_literal: true

module OpenAIAgents
  module Logging
    # Rails integration for OpenAI Agents logging
    #
    # This module provides Rails-specific logging integrations including:
    # - Request correlation IDs
    # - Rails tagged logging
    # - ActiveJob integration
    # - Rails configuration integration
    #
    module RailsIntegration
      class << self
        def setup!
          return unless defined?(Rails)

          configure_rails_logger
          setup_request_correlation
          setup_activejob_integration if defined?(ActiveJob)
          setup_rails_configuration
        end

        private

        def configure_rails_logger
          OpenAIAgents::Logging.configure do |config|
            config.log_output = :rails
            config.log_level = Rails.logger.level
          end
        end

        def setup_request_correlation
          # Middleware to add request correlation IDs
          return unless defined?(ActionDispatch)

          Rails.application.config.middleware.insert_before(
            ActionDispatch::RequestId,
            RequestCorrelationMiddleware
          )
        end

        def setup_activejob_integration
          ActiveJob::Base.class_eval do
            around_perform do |job, block|
              OpenAIAgents::Logging.info(
                "ActiveJob started",
                job_class: job.class.name,
                job_id: job.job_id,
                queue: job.queue_name
              )

              start_time = Time.current
              block.call
              duration = ((Time.current - start_time) * 1000).round(2)

              OpenAIAgents::Logging.info(
                "ActiveJob completed",
                job_class: job.class.name,
                job_id: job.job_id,
                duration_ms: duration
              )
            rescue StandardError => e
              OpenAIAgents::Logging.error(
                "ActiveJob failed",
                job_class: job.class.name,
                job_id: job.job_id,
                error: e.message,
                error_class: e.class.name
              )
              raise
            end
          end
        end

        def setup_rails_configuration
          # Add Rails configuration options
          Rails.application.config.openai_agents = ActiveSupport::OrderedOptions.new
          Rails.application.config.openai_agents.logging = ActiveSupport::OrderedOptions.new
          Rails.application.config.openai_agents.logging.enabled = true
          Rails.application.config.openai_agents.logging.level = :info
          Rails.application.config.openai_agents.logging.format = :text
        end
      end

      # Middleware for request correlation
      class RequestCorrelationMiddleware
        def initialize(app)
          @app = app
        end

        def call(env)
          request_id = env["action_dispatch.request_id"] || SecureRandom.hex(8)

          # Store request ID in thread-local storage
          Thread.current[:openai_agents_request_id] = request_id

          @app.call(env)
        ensure
          Thread.current[:openai_agents_request_id] = nil
        end
      end

      # Enhanced Rails logger adapter with tagging
      class EnhancedRailsLoggerAdapter < RailsLoggerAdapter
        def initialize(rails_logger, config)
          super
          @rails_logger = rails_logger
        end

        def debug(message)
          log_with_tags(:debug, message)
        end

        def info(message)
          log_with_tags(:info, message)
        end

        def warn(message)
          log_with_tags(:warn, message)
        end

        def error(message)
          log_with_tags(:error, message)
        end

        def fatal(message)
          log_with_tags(:fatal, message)
        end

        private

        def log_with_tags(level, message)
          tags = build_tags

          if @rails_logger.respond_to?(:tagged)
            @rails_logger.tagged(*tags) do
              @rails_logger.send(level, message)
            end
          else
            tagged_message = "[#{tags.join("][")}] #{message}"
            @rails_logger.send(level, tagged_message)
          end
        end

        def build_tags
          tags = ["OpenAI-Agents"]

          if (request_id = Thread.current[:openai_agents_request_id])
            tags << "req:#{request_id}"
          end

          if (trace_id = current_trace_id)
            tags << "trace:#{trace_id[0..7]}"
          end

          tags
        end

        def current_trace_id
          # Get current trace ID from tracing system
          return nil unless defined?(OpenAIAgents::Tracing)

          OpenAIAgents::Tracing.current_trace&.trace_id
        end
      end
    end
  end
end

# Auto-setup when Rails is loaded
if defined?(Rails)
  Rails.application.config.to_prepare do
    OpenAIAgents::Logging::RailsIntegration.setup!
  end
end
