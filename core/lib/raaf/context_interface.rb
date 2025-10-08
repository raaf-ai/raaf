# frozen_string_literal: true

module RAAF

  ##
  # Unified Context Interface for RAAF
  #
  # This module defines the standard interface that all RAAF context classes
  # should implement for consistent data access patterns across the framework.
  #
  # == Design Principles
  #
  # 1. **Indifferent Access**: All contexts support both symbol and string keys
  # 2. **Consistent API**: Same method names across all context types
  # 3. **Two-Tier Pattern**: Mutable (Core) and immutable (DSL) implementations
  #
  # == Tier 1: Mutable Core Contexts
  #
  # Core contexts (RunContext, ToolContext, HandoffContext) use mutable operations
  # for performance in tight loops and frequent updates:
  #
  #   context.set(:key, "value")  # Modifies context in place
  #   context.get(:key)            # => "value"
  #
  # == Tier 2: Immutable DSL Contexts
  #
  # DSL contexts (ContextVariables, derivatives) use immutable operations
  # for safety in user-facing code:
  #
  #   context1 = context.set(:key, "value")  # Returns NEW instance
  #   context != context1                     # True - different objects
  #
  # == Interface Methods
  #
  # All conforming contexts must implement:
  #
  # === Data Access
  # - get(key, default = nil)     # Read value with optional default
  # - set(key, value)             # Write value (tier 1: mutate, tier 2: return new)
  # - delete(key)                 # Remove value
  # - has?(key)                   # Check existence (aliases: key?, include?)
  #
  # === Bulk Operations
  # - keys                        # All keys
  # - values                      # All values
  # - to_h                        # Export as hash
  # - update(hash)                # Merge data (tier 1: mutate, tier 2: return new)
  #
  # === Array-Style Access
  # - [](key)                     # Read: context[:key]
  # - []=(key, value)             # Write: context[:key] = value
  #
  # == Indifferent Access Requirement
  #
  # **ALL contexts MUST support both symbol and string keys at all nesting levels**:
  #
  #   context[:user][:profile][:name]        # Works
  #   context["user"]["profile"]["name"]     # Works
  #   context[:user]["profile"][:name]       # Mixed works too
  #
  # == Usage Examples
  #
  #   # Mutable context (Core)
  #   run_context = RunContext.new
  #   run_context.set(:user_id, "123")       # Mutates in place
  #   run_context[:session] = "abc"          # Array-style write
  #   user_id = run_context.get(:user_id)   # => "123"
  #   user_id = run_context["user_id"]      # => "123" (indifferent)
  #
  #   # Immutable context (DSL)
  #   ctx = ContextVariables.new
  #   ctx1 = ctx.set(:key, "value")          # Returns new instance
  #   ctx != ctx1                            # True - immutable
  #
  # @author RAAF (Ruby AI Agents Factory) Team
  # @since 0.8.0
  # @see RunContext Mutable conversation context
  # @see ToolContext Mutable tool execution context
  # @see HandoffContext Mutable agent handoff context
  # @see ContextVariables Immutable DSL context
  #
  module ContextInterface

    ##
    # Get value from context
    #
    # @param key [Symbol, String] The context key
    # @param default [Object] Default value if key not found
    # @return [Object] The stored value or default
    #
    # @example
    #   context.get(:user_id, "unknown")  # => "123" or "unknown"
    #   context.get("user_id")            # => "123" (indifferent access)
    #
    def get(key, default = nil)
      raise NotImplementedError, "#{self.class} must implement #get"
    end

    ##
    # Set value in context
    #
    # **Tier 1 (Mutable)**: Modifies context in place and returns value
    # **Tier 2 (Immutable)**: Returns new context instance with value set
    #
    # @param key [Symbol, String] The context key
    # @param value [Object] The value to store
    # @return [Object, ContextInterface] Value (tier 1) or new context (tier 2)
    #
    # @example Mutable (Core)
    #   context.set(:key, "value")  # Returns "value", modifies context
    #
    # @example Immutable (DSL)
    #   ctx1 = context.set(:key, "value")  # Returns new context instance
    #   context != ctx1                     # True - different objects
    #
    def set(key, value)
      raise NotImplementedError, "#{self.class} must implement #set"
    end

    ##
    # Delete key from context
    #
    # @param key [Symbol, String] The context key
    # @return [Object, nil] The deleted value or nil
    #
    # @example
    #   context.delete(:key)   # Removes key, returns old value
    #   context.delete("key")  # Indifferent access
    #
    def delete(key)
      raise NotImplementedError, "#{self.class} must implement #delete"
    end

    ##
    # Check if key exists in context
    #
    # @param key [Symbol, String] The context key
    # @return [Boolean] true if key exists
    #
    # @example
    #   context.has?(:key)   # => true
    #   context.has?("key")  # => true (indifferent)
    #
    def has?(key)
      raise NotImplementedError, "#{self.class} must implement #has?"
    end

    ##
    # Array-style read access
    #
    # @param key [Symbol, String] The context key
    # @return [Object, nil] The stored value or nil
    #
    # @example
    #   context[:user_id]   # => "123"
    #   context["user_id"]  # => "123" (indifferent)
    #
    def [](key)
      get(key)
    end

    ##
    # Array-style write access
    #
    # @param key [Symbol, String] The context key
    # @param value [Object] The value to store
    # @return [Object] The stored value
    #
    # @example
    #   context[:user_id] = "123"
    #   context["user_id"] = "123"  # Indifferent
    #
    def []=(key, value)
      set(key, value)
      value
    end

    ##
    # Get all context keys
    #
    # @return [Array<Symbol, String>] All keys in context
    #
    # @example
    #   context.keys  # => [:user_id, :session]
    #
    def keys
      raise NotImplementedError, "#{self.class} must implement #keys"
    end

    ##
    # Get all context values
    #
    # @return [Array<Object>] All values in context
    #
    # @example
    #   context.values  # => ["123", "abc"]
    #
    def values
      raise NotImplementedError, "#{self.class} must implement #values"
    end

    ##
    # Export context as hash
    #
    # @return [Hash] The context data with indifferent access
    #
    # @example
    #   context.to_h  # => { user_id: "123", session: "abc" }
    #
    def to_h
      raise NotImplementedError, "#{self.class} must implement #to_h"
    end

    ##
    # Update context with multiple values
    #
    # **Tier 1 (Mutable)**: Modifies context in place and returns context
    # **Tier 2 (Immutable)**: Returns new context instance with merged values
    #
    # @param hash [Hash] Hash of key-value pairs to merge
    # @return [Hash, ContextInterface] Context hash (tier 1) or new instance (tier 2)
    #
    # @example Mutable (Core)
    #   context.update(user: "John", age: 30)  # Modifies context
    #
    # @example Immutable (DSL)
    #   ctx1 = context.update(user: "John")    # Returns new instance
    #   context != ctx1                         # True
    #
    def update(hash)
      raise NotImplementedError, "#{self.class} must implement #update"
    end

    ##
    # Check if context is empty
    #
    # @return [Boolean] true if context has no data
    #
    # @example
    #   context.empty?  # => false
    #
    def empty?
      keys.empty?
    end

    ##
    # Get number of items in context
    #
    # @return [Integer] Number of key-value pairs
    #
    # @example
    #   context.size  # => 2
    #
    def size
      keys.size
    end

    ##
    # Alias for has?
    #
    alias_method :key?, :has?

    ##
    # Alias for has?
    #
    alias_method :include?, :has?

  end

end
