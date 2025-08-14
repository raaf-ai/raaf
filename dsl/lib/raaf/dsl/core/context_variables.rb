# frozen_string_literal: true

# Swarm-style context variables management with debugging support
#
# This class provides OpenAI Swarm-compatible context variable handling with
# comprehensive debugging capabilities. It tracks all context state changes,
# provides serialization for handoffs, and includes detailed logging for
# debugging multi-agent workflows.
#
# Key features:
# - Immutable context updates (Swarm-style)
# - Change tracking and debugging hooks
# - JSON serialization for persistence
# - Type validation and contracts
# - Performance monitoring
#
# @example Basic usage
#   context = RAAF::DSL::ContextVariables.new(session_id: "123", user_tier: "premium")
#   updated = context.update(request_analyzed: true, priority: "high")
#   puts updated.get(:priority) # => "high"
#
# @example With debugging
#   context = RAAF::DSL::ContextVariables.new({ user: "john" }, debug: true)
#   context.update(step: "analysis") # Logs the update
#
# @since 0.2.0
#
module RAAF
  module DSL
    class ContextVariables
      # Error raised when context variable operations fail
      class ContextError < StandardError; end

      # @return [Hash] The current context variables
      attr_reader :variables

      # @return [Array<Hash>] History of context changes for debugging
      attr_reader :change_history

      # @return [Boolean] Whether debug mode is enabled
      attr_reader :debug_enabled

      # Initialize a new ContextVariables instance
      #
      # @param initial_variables [Hash] Initial context variables
      # @param debug [Boolean] Enable debug logging and change tracking
      # @param validate [Boolean] Enable type validation (default: true)
      #
      # @example
      #   context = RAAF::DSL::ContextVariables.new(
      #     session_id: "abc-123",
      #     user_tier: "premium",
      #     debug: true
      #   )
      #
      def initialize(initial_variables = {}, **options)
        @variables = initial_variables.is_a?(Hash) ? initial_variables.dup : {}
        @debug_enabled = options[:debug] || false
        @validate_enabled = options[:validate] != false # Default to true unless explicitly false
        @change_history = []

        # Convert string keys to symbols for consistency
        @variables = symbolize_keys(@variables)
        @created_at = Time.now

        debug_log("Context Initialized", variables: @variables)
        validate_variables! if @validate_enabled
      end

      # Create a new ContextVariables instance with updated values (immutable)
      #
      # This method follows the OpenAI Swarm pattern of immutable context updates.
      # It returns a new instance with the merged variables, preserving the original.
      #
      # @param new_variables [Hash] Variables to add or update
      # @return [ContextVariables] New instance with updated variables
      #
      # @example
      #   original = RAAF::DSL::ContextVariables.new(step: 1)
      #   updated = original.update(step: 2, result: "success")
      #   original.get(:step) # => 1 (unchanged)
      #   updated.get(:step)  # => 2 (new instance)
      #
      def update(new_variables = {})
        return self if new_variables.nil? || new_variables.empty?

        new_variables = symbolize_keys(new_variables)
        merged_variables = @variables.merge(new_variables)

        # Track changes for debugging
        changes = calculate_changes(@variables, merged_variables)

        debug_log("Context Update", {
                    before: @variables,
                    updates: new_variables,
                    after: merged_variables,
                    changes: changes
                  })

        # Create new instance
        new_instance = self.class.new(
          merged_variables,
          debug: @debug_enabled,
          validate: @validate_enabled
        )

        # Copy change history and add this update
        new_instance.instance_variable_set(:@change_history, @change_history.dup)
        new_instance.add_to_history(changes)

        new_instance
      end

      # Get a context variable value
      #
      # This method supports accessing both regular values and ObjectProxy instances.
      # When a proxy is accessed, it returns the proxy itself for lazy evaluation.
      #
      # @param key [Symbol, String] The variable key
      # @param default [Object] Default value if key doesn't exist
      # @return [Object] The variable value or default
      #
      # @example Regular value
      #   context.get(:user_tier, "standard") # => "premium" or "standard"
      #
      # @example Proxied object
      #   context.get(:product).name # => Lazy loads product.name
      #
      def get(key, default = nil)
        value = @variables[key.to_sym]
        value.nil? ? default : value
      end

      # Get a nested value using a path array (for prompt system compatibility)
      #
      # @param path [Array<Symbol, String>] Path to the nested value
      # @param default [Object] Default value if path doesn't exist
      # @return [Object] The nested value or default
      #
      # @example
      #   context.get_nested([:document, :name]) # => "report.pdf"
      #   context.get_nested([:processing_params, :analysis_type], "standard") # => "detailed" or "standard"
      #
      def get_nested(path, default = nil)
        return default if path.nil? || path.empty?

        value = @variables
        path.each do |key|
          value = value&.dig(key.to_sym) || value&.[](key.to_sym)
          break if value.nil?
        end

        value || default
      end

      # Set a single variable (returns new instance)
      #
      # @param key [Symbol, String] The variable key
      # @param value [Object] The variable value
      # @return [ContextVariables] New instance with the variable set
      #
      # @example
      #   updated = context.set(:priority, "high")
      #
      def set(key, value)
        update(key.to_sym => value)
      end

      # Check if a variable exists
      #
      # @param key [Symbol, String] The variable key
      # @return [Boolean] True if the variable exists
      #
      def has?(key)
        @variables.key?(key.to_sym)
      end
      alias key? has?
      alias include? has?

      # Get all variable keys
      #
      # @return [Array<Symbol>] Array of variable keys
      #
      def keys
        @variables.keys
      end

      # Get the number of variables
      #
      # @return [Integer] Number of context variables
      #
      def size
        @variables.size
      end
      alias length size

      # Check if context is empty
      #
      # @return [Boolean] True if no variables are set
      #
      def empty?
        @variables.empty?
      end

      # Convert to hash (for compatibility)
      #
      # This method serializes ObjectProxy instances when converting to hash,
      # ensuring that the hash representation contains actual data rather than proxies.
      #
      # @param options [Hash] Serialization options
      # @option options [Boolean] :serialize_proxies Whether to serialize proxy objects (default: true)
      # @return [Hash] Hash representation of context variables
      #
      def to_h(options = {})
        serialize_proxies = options.fetch(:serialize_proxies, true)
        
        if serialize_proxies
          require_relative 'object_proxy' unless defined?(RAAF::DSL::ObjectProxy)
          
          @variables.transform_values do |value|
            if value.respond_to?(:proxy?) && value.proxy?
              value.to_serialized_hash
            else
              value
            end
          end
        else
          @variables.dup
        end
      end
      alias to_hash to_h

      # JSON serialization support
      #
      # @return [String] JSON representation of context variables
      #
      def to_json(*args)
        to_h.to_json(*args)
      end

      # Create ContextVariables from JSON
      #
      # @param json [String] JSON string to parse
      # @param debug [Boolean] Enable debug mode
      # @return [ContextVariables] New instance from JSON
      #
      def self.from_json(json, debug: false)
        variables = JSON.parse(json, symbolize_names: true)
        new(variables, debug: debug)
      end

      # Merge with another ContextVariables instance
      #
      # @param other [ContextVariables, Hash] Other context to merge
      # @return [ContextVariables] New merged instance
      #
      def merge(other)
        other_vars = other.is_a?(self.class) ? other.to_h : other
        update(other_vars)
      end

      # Create a snapshot for debugging
      #
      # @return [Hash] Complete debug snapshot
      #
      def debug_snapshot
        {
          variables: @variables.dup,
          change_history: @change_history.dup,
          debug_enabled: @debug_enabled,
          created_at: @created_at,
          snapshot_at: Time.now,
          variable_count: size,
          memory_usage: debug_memory_usage
        }
      end

      # Get formatted debug information
      #
      # @param include_history [Boolean] Include change history
      # @return [String] Formatted debug information
      #
      def debug_info(include_history: true)
        info = []
        info << "🔍 Context Variables Debug Info"
        info << ("-" * 40).to_s
        info << "Variables (#{size}):"

        @variables.each do |key, value|
          info << "  #{key}: #{value.inspect}"
        end

        if include_history && @change_history.any?
          info << ""
          info << "Change History (#{@change_history.size} changes):"
          @change_history.last(5).each_with_index do |change, i|
            info << "  #{i + 1}. #{change[:timestamp]} - #{change[:summary]}"
            change[:details].each do |detail|
              info << "     #{detail}"
            end
          end
        end

        info.join("\n")
      end

      # Compare with another ContextVariables instance
      #
      # @param other [ContextVariables] Other instance to compare
      # @return [Hash] Comparison details
      #
      def diff(other)
        return { identical: true } if @variables == other.to_h

        other_vars = other.to_h
        added = other_vars.reject { |k, _| @variables.key?(k) }
        removed = @variables.reject { |k, _| other_vars.key?(k) }
        changed = {}

        @variables.each do |key, value|
          changed[key] = { from: value, to: other_vars[key] } if other_vars.key?(key) && other_vars[key] != value
        end

        {
          identical: false,
          added: added,
          removed: removed,
          changed: changed,
          summary: "#{added.size} added, #{removed.size} removed, #{changed.size} changed"
        }
      end

      protected

      # Add change to history (for debugging)
      #
      # @param changes [Hash] Change details
      # @api private
      #
      def add_to_history(changes)
        @change_history << {
          timestamp: Time.now,
          changes: changes,
          summary: summarize_changes(changes),
          details: format_change_details(changes)
        }

        # Keep history size manageable
        @change_history.shift if @change_history.size > 100
      end

      private

      # Convert string keys to symbols
      def symbolize_keys(hash)
        return hash unless hash.is_a?(Hash)

        hash.transform_keys(&:to_sym)
      end

      # Calculate changes between two variable sets
      def calculate_changes(before, after)
        added = after.reject { |k, _| before.key?(k) }
        removed = before.reject { |k, _| after.key?(k) }
        modified = {}

        before.each do |key, value|
          modified[key] = { from: value, to: after[key] } if after.key?(key) && after[key] != value
        end

        {
          added: added,
          removed: removed,
          modified: modified,
          total_changes: added.size + removed.size + modified.size
        }
      end

      # Summarize changes for history
      def summarize_changes(changes)
        parts = []
        parts << "#{changes[:added].size} added" if changes[:added].any?
        parts << "#{changes[:removed].size} removed" if changes[:removed].any?
        parts << "#{changes[:modified].size} modified" if changes[:modified].any?

        parts.any? ? parts.join(", ") : "no changes"
      end

      # Format change details for debugging
      def format_change_details(changes)
        details = changes[:added].map do |key, value|
          "➕ #{key}: #{value.inspect}"
        end

        changes[:removed].each do |key, value|
          details << "➖ #{key}: #{value.inspect}"
        end

        changes[:modified].each do |key, change|
          details << "🔄 #{key}: #{change[:from].inspect} → #{change[:to].inspect}"
        end

        details
      end

      # Debug logging helper
      def debug_log(action, data = {})
        return unless @debug_enabled

        # Ensure proxies are handled properly in debug output
        debug_data = data.transform_values do |value|
          if value.is_a?(Hash)
            value.transform_values do |v|
              (v.respond_to?(:proxy?) && v.proxy?) ? "<ObjectProxy:#{v.__target__.class.name}>" : v
            end
          else
            (value.respond_to?(:proxy?) && value.proxy?) ? "<ObjectProxy:#{value.__target__.class.name}>" : value
          end
        end

        RAAF::Logging.debug("[ContextVariables] #{action}", category: :context, data: debug_data)
      end

      # Basic variable validation
      def validate_variables!
        return unless @validate_enabled

        @variables.each do |key, value|
          # Check for invalid keys
          unless key.is_a?(Symbol) || key.is_a?(String)
            raise ContextError, "Invalid context key type: #{key.class}. Must be Symbol or String"
          end

          # Check for non-serializable values (in strict mode)
          if value.is_a?(Proc) || value.is_a?(Method)
            debug_log("Warning: Non-serializable value for key #{key}: #{value.class}")
          end
        end
      end

      # Debug memory usage (approximate)
      def debug_memory_usage
        # Rough estimate of memory usage
        estimated_size = @variables.inspect.bytesize + @change_history.inspect.bytesize
        "~#{estimated_size} bytes"
      end
    end
  end
end
