# frozen_string_literal: true

module RAAF
  module Continuation
    # Configuration class for continuation behavior
    #
    # This class encapsulates all configuration options for automatic continuation
    # support in RAAF agents, including retry limits, output formats, and failure
    # handling strategies.
    #
    # @example Basic configuration with defaults
    #   config = RAAF::Continuation::Config.new
    #   config.max_attempts  # => 10
    #   config.output_format # => :auto
    #
    # @example Custom configuration
    #   config = RAAF::Continuation::Config.new(
    #     max_attempts: 15,
    #     output_format: :csv,
    #     on_failure: :raise_error
    #   )
    class Config
      # Valid output format options
      VALID_FORMATS = [:csv, :markdown, :json, :auto].freeze

      # Valid failure handling modes
      VALID_FAILURE_MODES = [:return_partial, :raise_error].freeze

      # Maximum allowed attempts for continuation
      MAX_ATTEMPTS_LIMIT = 50

      # Default configuration values
      DEFAULTS = {
        max_attempts: 10,
        output_format: :auto,
        on_failure: :return_partial,
        merge_strategy: nil  # Format-specific, determined at runtime
      }.freeze

      # @return [Integer] Maximum number of continuation attempts (1-50)
      attr_accessor :max_attempts

      # @return [Symbol] Output format (:csv, :markdown, :json, :auto)
      attr_accessor :output_format

      # @return [Symbol] Failure handling mode (:return_partial, :raise_error)
      attr_accessor :on_failure

      # @return [Symbol, nil] Internal merge strategy (format-specific)
      attr_accessor :merge_strategy

      # Initialize a new continuation configuration
      #
      # @param options [Hash] Configuration options
      # @option options [Integer] :max_attempts (10) Maximum continuation attempts (1-50)
      # @option options [Symbol, String] :output_format (:auto) Output format
      # @option options [Symbol, String] :on_failure (:return_partial) Failure handling mode
      # @option options [Symbol, nil] :merge_strategy (nil) Internal merge strategy
      #
      # @raise [InvalidConfigurationError] If any configuration value is invalid
      #
      # @example Create with custom options
      #   config = Config.new(max_attempts: 20, output_format: :csv)
      def initialize(options = {})
        # Apply defaults first
        @max_attempts = DEFAULTS[:max_attempts]
        @output_format = DEFAULTS[:output_format]
        @on_failure = DEFAULTS[:on_failure]
        @merge_strategy = DEFAULTS[:merge_strategy]

        # Check for unknown options
        known_options = [:max_attempts, :output_format, :on_failure, :merge_strategy]
        unknown_options = options.keys - known_options
        unless unknown_options.empty?
          raise RAAF::InvalidConfigurationError,
                "Unknown continuation option: #{unknown_options.first}. " \
                "Valid options are: #{known_options.join(', ')}"
        end

        # Override with provided options (converting strings to symbols if needed)
        options.each do |key, value|
          case key
          when :max_attempts
            @max_attempts = value
          when :output_format
            @output_format = normalize_symbol_value(value)
          when :on_failure
            @on_failure = normalize_symbol_value(value)
          when :merge_strategy
            @merge_strategy = value.nil? ? nil : normalize_symbol_value(value)
          end
        end

        # Validate all configuration immediately
        validate!
      end

      # Validate all configuration values
      #
      # @raise [InvalidConfigurationError] If any configuration value is invalid
      #
      # @return [true] Returns true if validation passes
      def validate!
        validate_max_attempts!
        validate_output_format!
        validate_on_failure!
        true
      end

      # Check if configuration is valid
      #
      # @return [Boolean] true if valid, false otherwise
      def valid?
        validate!
        true
      rescue RAAF::InvalidConfigurationError
        false
      end

      # Convert configuration to hash
      #
      # @return [Hash] Configuration as a hash with symbol keys
      def to_h
        {
          max_attempts: max_attempts,
          output_format: output_format,
          on_failure: on_failure,
          merge_strategy: merge_strategy
        }
      end

      # Check equality with another config
      #
      # @param other [Config] Another config to compare
      # @return [Boolean] true if configs are equal
      def ==(other)
        return false unless other.is_a?(Config)

        max_attempts == other.max_attempts &&
          output_format == other.output_format &&
          on_failure == other.on_failure &&
          merge_strategy == other.merge_strategy
      end

      private

      # Normalize string values to symbols
      #
      # @param value [String, Symbol] Value to normalize
      # @return [Symbol] Normalized symbol value
      def normalize_symbol_value(value)
        return value if value.is_a?(Symbol)
        return value.to_sym if value.respond_to?(:to_sym)

        value
      end

      # Validate max_attempts configuration
      #
      # @raise [InvalidConfigurationError] If max_attempts is invalid
      def validate_max_attempts!
        if max_attempts.nil?
          raise RAAF::InvalidConfigurationError,
                "max_attempts must be a positive integer between 1 and #{MAX_ATTEMPTS_LIMIT}, got nil"
        end

        unless max_attempts.is_a?(Integer)
          raise RAAF::InvalidConfigurationError,
                "max_attempts must be a positive integer between 1 and #{MAX_ATTEMPTS_LIMIT}, got #{max_attempts.class.name}"
        end

        if max_attempts <= 0
          raise RAAF::InvalidConfigurationError,
                "max_attempts must be a positive integer between 1 and #{MAX_ATTEMPTS_LIMIT}, got #{max_attempts}"
        end

        if max_attempts > MAX_ATTEMPTS_LIMIT
          raise RAAF::InvalidConfigurationError,
                "max_attempts cannot exceed #{MAX_ATTEMPTS_LIMIT}, got #{max_attempts}"
        end
      end

      # Validate output_format configuration
      #
      # @raise [InvalidConfigurationError] If output_format is invalid
      def validate_output_format!
        if output_format.nil? || output_format == "" || output_format.to_s.strip.empty?
          raise RAAF::InvalidConfigurationError,
                "Invalid output_format: #{output_format.inspect}. " \
                "Valid options are: #{VALID_FORMATS.map(&:inspect).join(', ')}"
        end

        unless VALID_FORMATS.include?(output_format)
          suggestion = suggest_similar_option(output_format, VALID_FORMATS)
          message = "Invalid output_format: #{output_format}. " \
                   "Valid options are: #{VALID_FORMATS.map(&:inspect).join(', ')}"
          message += ". Did you mean: :#{suggestion}" if suggestion

          raise RAAF::InvalidConfigurationError, message
        end
      end

      # Validate on_failure configuration
      #
      # @raise [InvalidConfigurationError] If on_failure is invalid
      def validate_on_failure!
        unless VALID_FAILURE_MODES.include?(on_failure)
          suggestion = suggest_similar_option(on_failure, VALID_FAILURE_MODES)
          message = "Invalid on_failure mode: #{on_failure}. " \
                   "Valid options are: #{VALID_FAILURE_MODES.map(&:inspect).join(', ')}"
          message += ". Did you mean: :#{suggestion}" if suggestion

          raise RAAF::InvalidConfigurationError, message
        end
      end

      # Suggest similar valid option based on edit distance
      #
      # @param invalid_option [Symbol, String] The invalid option provided
      # @param valid_options [Array<Symbol>] List of valid options
      # @return [Symbol, nil] Suggested option or nil if no close match
      def suggest_similar_option(invalid_option, valid_options)
        return nil unless invalid_option

        invalid_str = invalid_option.to_s.downcase

        # Check for close matches (e.g., return_partials -> return_partial)
        close_matches = valid_options.select do |valid|
          valid_str = valid.to_s.downcase
          levenshtein_distance(invalid_str, valid_str) <= 2 ||
            valid_str.include?(invalid_str) ||
            invalid_str.include?(valid_str)
        end

        close_matches.min_by { |match| levenshtein_distance(invalid_str, match.to_s.downcase) }
      end

      # Calculate Levenshtein distance between two strings
      #
      # @param str1 [String] First string
      # @param str2 [String] Second string
      # @return [Integer] Edit distance between strings
      def levenshtein_distance(str1, str2)
        m = str1.length
        n = str2.length
        return m if n == 0
        return n if m == 0

        # Create distance matrix
        d = Array.new(m + 1) { Array.new(n + 1) }

        # Initialize first column and row
        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }

        # Calculate distances
        (1..n).each do |j|
          (1..m).each do |i|
            cost = str1[i - 1] == str2[j - 1] ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,      # deletion
              d[i][j - 1] + 1,      # insertion
              d[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        d[m][n]
      end
    end
  end
end