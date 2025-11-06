# frozen_string_literal: true

require "logger"

module RAAF
  module Eval
    ##
    # Configuration for RAAF Eval
    #
    # Manages global settings including database connection, logging,
    # and AI comparator configuration.
    class Configuration
      # @return [String, nil] Database URL for PostgreSQL connection
      attr_accessor :database_url

      # @return [Logger] Logger instance for RAAF Eval
      attr_accessor :logger

      # @return [String] Model to use for AI comparator (default: "gpt-4o")
      attr_accessor :ai_comparator_model

      # @return [Boolean] Whether to enable AI comparator (default: true)
      attr_accessor :enable_ai_comparator

      # @return [Integer] Timeout for AI comparator requests in seconds (default: 30)
      attr_accessor :ai_comparator_timeout

      ##
      # Initialize configuration with defaults
      def initialize
        @database_url = ENV["DATABASE_URL"]
        @logger = Logger.new($stdout, level: Logger::INFO)
        @ai_comparator_model = "gpt-4o"
        @enable_ai_comparator = true
        @ai_comparator_timeout = 30
      end

      ##
      # Establish database connection using configured URL
      #
      # @raise [ConfigurationError] if database_url is not set
      def establish_connection!
        raise ConfigurationError, "database_url must be set" unless database_url

        ActiveRecord::Base.establish_connection(database_url)
        logger.info("RAAF Eval database connection established")
      end
    end
  end
end
