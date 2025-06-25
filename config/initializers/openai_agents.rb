# frozen_string_literal: true

# OpenAI Agents Configuration
#
# This initializer configures the OpenAI Agents gem for your Rails application.
# It sets up tracing with the ActiveRecord processor to store traces in your database.

# Ensure the gem is loaded
require "openai_agents"

# Configure tracing with ActiveRecord processor
# This will store all agent traces and spans in your Rails database
if (defined?(Rails) && Rails.env.development?) || Rails.env.production?
  # Add the ActiveRecord processor to store traces in the database
  OpenAIAgents.tracer.add_processor(
    OpenAIAgents::Tracing::ActiveRecordProcessor.new(
      # Sampling rate: 1.0 = 100% of traces, 0.1 = 10% of traces
      sampling_rate: 1.0,

      # Batch size for database operations (higher = better performance, more memory)
      batch_size: 50,

      # Enable automatic cleanup of old traces
      auto_cleanup: true,

      # Delete traces older than 30 days
      cleanup_older_than: 30.days
    )
  )

  Rails.logger.info "[OpenAI Agents] Tracing configured with ActiveRecord processor"
end

# Optional: Add OpenAI processor to send traces to OpenAI dashboard
# Uncomment the following lines if you want to send traces to OpenAI
# if ENV['OPENAI_API_KEY'].present?
#   OpenAIAgents.tracer.add_processor(
#     OpenAIAgents::Tracing::OpenAIProcessor.new
#   )
#   Rails.logger.info "[OpenAI Agents] Tracing configured with OpenAI processor"
# end

# Optional: Configure default model
# OpenAIAgents.configure do |config|
#   config.default_model = "gpt-4o"
# end

# Optional: Mount the tracing engine in your routes.rb file:
# mount OpenAIAgents::Tracing::Engine => '/tracing'
