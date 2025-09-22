# frozen_string_literal: true

require 'active_support/core_ext/hash/indifferent_access'
require 'set'

# Swarm-style context variables management with debugging support and deep indifferent access
#
# This class provides OpenAI Swarm-compatible context variable handling with
# comprehensive debugging capabilities and deep HashWithIndifferentAccess support.
# It tracks all context state changes, provides serialization for handoffs, and
# includes detailed logging for debugging multi-agent workflows.
#
# Key features:
# - Immutable context updates (Swarm-style)
# - Deep HashWithIndifferentAccess for nested hashes and arrays
# - Change tracking and debugging hooks
# - JSON serialization for persistence
# - Type validation and contracts
# - Performance monitoring
#
# @example Basic usage with indifferent access
#   context = RAAF::DSL::ContextVariables.new(session_id: "123", user_tier: "premium")
#   updated = context.update(request_analyzed: true, priority: "high")
#   puts updated.get(:priority) # => "high"
#   puts updated.get("priority") # => "high" (same result)
#
# @example Deep indifferent access for nested structures
#   context = RAAF::DSL::ContextVariables.new(
#     user: { profile: { name: "John", settings: { theme: "dark" } } },
#     items: [{ id: 1, metadata: { type: "document" } }]
#   )
#   
#   # All of these work identically:
#   puts context[:user][:profile][:name]        # => "John"
#   puts context["user"]["profile"]["name"]     # => "John"
#   puts context[:user]["profile"][:name]       # => "John"
#   
#   # Arrays containing hashes also support indifferent access:
#   first_item = context[:items].first
#   puts first_item[:id]           # => 1
#   puts first_item["id"]          # => 1
#   puts first_item[:metadata][:type]  # => "document"
#   puts first_item["metadata"]["type"] # => "document"
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
        # Extract debug and validation options from keyword arguments
        @debug_enabled = options.delete(:debug) || false
        @validate_enabled = options.delete(:validate) != false # Default to true unless explicitly false
        @change_history = []

        # If initial_variables is empty but we have keyword arguments,
        # use the keyword arguments as the initial variables
        actual_variables = if initial_variables.empty? && !options.empty?
                            options
                          else
                            initial_variables
                          end
        
        # Use deep indifferent access to eliminate string vs symbol key issues in nested structures
        @variables = case actual_variables
                     when ActiveSupport::HashWithIndifferentAccess
                       deep_convert_to_indifferent_access(actual_variables.dup)
                     when Hash
                       deep_convert_to_indifferent_access(actual_variables)
                     else
                       {}.with_indifferent_access
                     end
        
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

        # Convert new variables to deep indifferent access
        new_variables = new_variables.is_a?(Hash) ? deep_convert_to_indifferent_access(new_variables) : new_variables
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
        # With indifferent access, we can use key as-is (string or symbol)
        value = @variables[key]
        value.nil? ? default : value
      end

      # Array-style access for compatibility with Hash syntax
      #
      # This allows ContextVariables to be used interchangeably with Hash
      # in agent code, making it easier to write portable agent implementations.
      #
      # @param key [Symbol, String] The variable key
      # @return [Object] The variable value or nil
      #
      # @example
      #   context[:user_tier] # => "premium"
      #   context["session_id"] # => "abc-123"
      #
      def [](key)
        get(key)
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
          # With indifferent access, no need to convert to symbol
          value = value&.dig(key)
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
        # With indifferent access, no need to convert key
        update(key => value)
      end

      # Check if a variable exists
      #
      # @param key [Symbol, String] The variable key
      # @return [Boolean] True if the variable exists
      #
      def has?(key)
        @variables.key?(key)
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
        variables = JSON.parse(json)
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

      # In-place merge that modifies the current instance
      #
      # @param other [Hash, ContextVariables] The data to merge
      # @return [ContextVariables] Self for chaining
      def merge!(other)
        other_vars = other.is_a?(self.class) ? other.to_h : other
        other_vars.each do |key, value|
          set(key, value)
        end
        self
      end

      # Hash-style assignment operator for convenience
      #
      # @param key [Symbol, String] The key to set
      # @param value [Object] The value to assign
      # @return [Object] The assigned value
      def []=(key, value)
        set(key, value)
        value
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

      # Enable splat operator (**) support for ContextVariables
      # Returns a hash with symbolized keys that can be splatted into keyword arguments
      # while preserving all object references (including ActiveRecord objects)
      #
      # @return [Hash] Hash with symbol keys suitable for keyword argument expansion
      #
      # @example Basic usage
      #   context = ContextVariables.new(product: product, company: company)
      #   MyAgent.new(**context)  # Works directly without .to_h conversion
      #
      # @example With ActiveRecord objects
      #   context = ContextVariables.new.set(:product, Product.find(1))
      #   agent = MyAgent.new(**context)  # product remains an ActiveRecord object
      #
      def to_hash
        @variables.symbolize_keys
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

      # Deep conversion of nested hashes and arrays to use indifferent access
      # This ensures that all nested structures support both string and symbol keys
      #
      # @param obj [Object] Object to convert
      # @param visited [Set] Set of visited object IDs to prevent circular references
      # @return [Object] Object with all nested hashes converted to indifferent access
      def deep_convert_to_indifferent_access(obj, visited = Set.new)
        # Prevent circular references by tracking visited objects
        if obj.is_a?(Hash) || obj.is_a?(Array)
          object_id = obj.object_id
          return obj if visited.include?(object_id)
          visited = visited.dup.add(object_id)
        end

        case obj
        when Hash
          # Convert hash to indifferent access and recursively convert all values
          # Use a safer approach to avoid infinite loops with circular references
          converted_hash = {}
          obj.each do |key, value|
            # Check if this value would cause a circular reference
            if (value.is_a?(Hash) || value.is_a?(Array)) && visited.include?(value.object_id)
              converted_hash[key] = "[CIRCULAR_REFERENCE]"
            else
              converted_hash[key] = deep_convert_to_indifferent_access(value, visited)
            end
          end
          converted_hash.with_indifferent_access
        when Array
          # Recursively convert all array elements
          obj.map { |element| deep_convert_to_indifferent_access(element, visited) }
        else
          # Return primitive values as-is
          obj
        end
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

        RAAF.logger.debug("[ContextVariables] #{action}", category: :context, data: debug_data)
      end

      # Basic variable validation
      def validate_variables!
        return unless @validate_enabled

        @variables.each do |key, value|
          # With indifferent access, keys are automatically normalized to strings
          # so we just check for basic validity
          unless key.respond_to?(:to_s)
            raise ContextError, "Invalid context key: #{key.inspect}. Must be convertible to string"
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
