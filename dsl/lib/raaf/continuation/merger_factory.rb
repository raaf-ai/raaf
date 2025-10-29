# frozen_string_literal: true

module RAAF
  module Continuation
    # MergerFactory routes to the appropriate format-specific merger
    #
    # This factory class selects the correct merger implementation based on
    # the configured output format. It supports explicit format selection
    # (:csv, :markdown, :json) as well as automatic format detection (:auto).
    #
    # When :auto format is used, MergerFactory uses FormatDetector to analyze
    # the content and select the most appropriate merger.
    #
    # @example Using a specific merger
    #   factory = MergerFactory.new(output_format: :csv)
    #   merger = factory.get_merger
    #   result = merger.merge(chunks)
    #
    # @example Using auto-detection
    #   factory = MergerFactory.new(output_format: :auto)
    #   merger = factory.get_merger_for_content(content)
    #   result = merger.merge(chunks)
    class MergerFactory
      # Default merger when format cannot be determined
      DEFAULT_FALLBACK_MERGER = RAAF::Continuation::Mergers::BaseMerger

      # Initialize the factory with configuration
      #
      # @param output_format [Symbol] Format indicator: :csv, :markdown, :json, :auto
      # @param logger [Logger] Logger for format detection results (optional)
      def initialize(output_format: :auto, logger: nil)
        @output_format = output_format
        @logger = logger || (defined?(Rails) && Rails.logger) || default_logger
      end

      # Get the appropriate merger instance for the configured format
      #
      # For explicit formats (:csv, :markdown, :json), returns the corresponding
      # merger. For :auto format, raises an error (use get_merger_for_content instead).
      #
      # @return [BaseMerger] An instance of the appropriate merger class
      #
      # @raise [ArgumentError] If format is :auto (must provide content)
      #
      # @example
      #   factory = MergerFactory.new(output_format: :csv)
      #   merger = factory.get_merger
      #   # => CSVMerger instance
      def get_merger
        case @output_format
        when :csv
          Mergers::CSVMerger.new
        when :markdown
          Mergers::MarkdownMerger.new
        when :json
          Mergers::JSONMerger.new
        when :auto
          raise ArgumentError, "Cannot get merger for :auto format without content. Use get_merger_for_content(content) instead."
        else
          log_warning("Unknown output format: #{@output_format}. Using default merger.")
          Mergers::BaseMerger.new
        end
      end

      # Get the appropriate merger based on content analysis
      #
      # When output_format is :auto, analyzes the content to determine
      # the most appropriate merger. For explicit formats, ignores content
      # and returns the configured merger.
      #
      # @param content [String] Content to analyze for format detection
      # @return [BaseMerger] An instance of the most appropriate merger
      #
      # @example
      #   factory = MergerFactory.new(output_format: :auto)
      #   merger = factory.get_merger_for_content(csv_data)
      #   # => CSVMerger instance (detected from content)
      def get_merger_for_content(content)
        if @output_format == :auto
          detected_format, confidence = detect_format(content)
          log_format_detection(detected_format, confidence)
          get_merger_for_format(detected_format)
        else
          get_merger
        end
      end

      # Detect the format of the given content
      #
      # Uses FormatDetector to analyze the content and determine its format.
      #
      # @param content [String] Content to analyze
      # @return [Array<Symbol, Float>] Detected format and confidence score
      #
      # @example
      #   factory = MergerFactory.new
      #   format, confidence = factory.detect_format(content)
      #   # => [:csv, 0.92]
      def detect_format(content)
        detector = FormatDetector.new
        detector.detect(content)
      end

      private

      # Get merger for a specific detected format
      #
      # @param format [Symbol] Detected format (:csv, :markdown, :json, :unknown)
      # @return [BaseMerger] Merger instance for the format
      private

      def get_merger_for_format(format)
        case format
        when :csv
          Mergers::CSVMerger.new
        when :markdown
          Mergers::MarkdownMerger.new
        when :json
          Mergers::JSONMerger.new
        else
          log_warning("Unable to detect format or unknown format. Using default merger.")
          Mergers::BaseMerger.new
        end
      end

      # Log format detection results
      #
      # @param format [Symbol] Detected format
      # @param confidence [Float] Confidence score (0.0-1.0)
      private

      def log_format_detection(format, confidence)
        confidence_percent = (confidence * 100).round(1)
        @logger.debug "📋 Format Detection: #{format} (confidence: #{confidence_percent}%)"
      end

      # Log a warning message
      #
      # @param message [String] Warning message
      private

      def log_warning(message)
        @logger.warn "⚠️ #{message}"
      end

      # Get a default logger if Rails is not available
      #
      # @return [Logger] A basic Ruby Logger instance
      private

      def default_logger
        require "logger"
        Logger.new($stdout)
      end
    end
  end
end
