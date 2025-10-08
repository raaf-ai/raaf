# frozen_string_literal: true

module RAAF

  ##
  # Manages handoff state and data transfer between agents
  #
  # This class provides explicit control over agent handoffs, replacing
  # the implicit hook-based system with direct function calling approach.
  #
  class HandoffContext

    include Logger

    attr_accessor :current_agent
    attr_reader :target_agent, :handoff_data, :shared_context, :handoff_timestamp

    def initialize(current_agent: nil)
      @current_agent = current_agent
      @target_agent = nil
      # Use HashWithIndifferentAccess for consistent key handling
      @handoff_data = {}.with_indifferent_access
      @shared_context = {}.with_indifferent_access
      @handoff_timestamp = nil
    end

    ##
    # Prepare handoff to target agent with structured data
    #
    # @param target_agent [String] Name of the target agent
    # @param data [Hash] Structured handoff data
    # @param reason [String] Reason for handoff
    # @return [Boolean] True if handoff was prepared successfully
    #
    def set_handoff(target_agent:, data:, reason: nil)
      @target_agent = target_agent
      @handoff_data = data.dup
      @handoff_timestamp = Time.now
      @shared_context.merge!(data)

      log_info("Handoff prepared",
               from: @current_agent,
               to: @target_agent,
               reason: reason,
               data_keys: data.keys)

      true
    end

    ##
    # Execute the handoff and update context
    #
    # @return [Hash] Handoff result with success status
    #
    def execute_handoff
      return { success: false, error: "No target agent set" } unless @target_agent

      previous_agent = @current_agent

      # Check for circular handoffs
      if handoff_chain.include?(@target_agent)
        return {
          success: false,
          error: "Circular handoff detected: #{@target_agent} already in chain #{handoff_chain}"
        }
      end

      @current_agent = @target_agent
      @target_agent = nil
      add_handoff(previous_agent, @current_agent)

      log_info("Handoff executed",
               from: previous_agent,
               to: @current_agent,
               timestamp: @handoff_timestamp)

      {
        success: true,
        previous_agent: previous_agent,
        current_agent: @current_agent,
        handoff_data: @handoff_data,
        timestamp: @handoff_timestamp
      }
    end

    ##
    # Check if handoff is pending
    #
    # @return [Boolean] True if handoff is ready to execute
    #
    def handoff_pending?
      !@target_agent.nil?
    end

    ##
    # Clear handoff state
    #
    def clear_handoff
      @target_agent = nil
      @handoff_data = {}.with_indifferent_access
      @handoff_timestamp = nil
    end

    ##
    # Get handoff data for target agent
    #
    # @param key [String, Symbol] Specific data key to retrieve
    # @return [Object] Handoff data or specific value
    #
    def get_handoff_data(key = nil)
      # HashWithIndifferentAccess handles symbol/string conversion automatically
      key ? @handoff_data[key] : @handoff_data
    end

    ##
    # Unified interface methods for RAAF context harmonization
    #

    ##
    # Get value from handoff data (unified interface)
    #
    # @param key [Symbol, String] The data key
    # @param default [Object] Default value if key not found
    # @return [Object] The stored value or default
    #
    def get(key, default = nil)
      @handoff_data.fetch(key, default)
    end

    ##
    # Set value in handoff data (unified interface)
    #
    # @param key [Symbol, String] The data key
    # @param value [Object] The value to store
    # @return [Object] The stored value
    #
    def set(key, value)
      @handoff_data[key] = value
    end

    ##
    # Check if key exists in handoff data (unified interface)
    #
    # @param key [Symbol, String] The data key
    # @return [Boolean] true if key exists
    #
    def has?(key)
      @handoff_data.key?(key)
    end

    ##
    # Array-style read access (unified interface)
    #
    # @param key [Symbol, String] The data key
    # @return [Object, nil] The stored value or nil
    #
    def [](key)
      @handoff_data[key]
    end

    ##
    # Array-style write access (unified interface)
    #
    # @param key [Symbol, String] The data key
    # @param value [Object] The value to store
    # @return [Object] The stored value
    #
    def []=(key, value)
      @handoff_data[key] = value
    end

    ##
    # Get all handoff data keys (unified interface)
    #
    # @return [Array<Symbol, String>] All keys in handoff data
    #
    def keys
      @handoff_data.keys
    end

    ##
    # Get all handoff data values (unified interface)
    #
    # @return [Array<Object>] All values in handoff data
    #
    def values
      @handoff_data.values
    end

    ##
    # Export handoff data as hash (unified interface)
    #
    # @return [Hash] The handoff data hash with indifferent access
    #
    def to_h
      @handoff_data.to_h
    end

    ##
    # Delete a key from handoff data (unified interface)
    #
    # @param key [Symbol, String] The data key
    # @return [Object, nil] The deleted value or nil
    #
    def delete(key)
      @handoff_data.delete(key)
    end

    ##
    # Update handoff data with multiple values (unified interface)
    #
    # @param hash [Hash] Hash of key-value pairs to merge
    # @return [Hash] The updated handoff data
    #
    def update(hash)
      @handoff_data.update(hash)
    end

    ##
    # Build initial message for handoff target agent
    #
    # @return [String] Formatted handoff message
    #
    def build_handoff_message
      return "" unless @handoff_data.any?

      message = "HANDOFF RECEIVED FROM #{@current_agent.upcase}\n"
      message += "TIMESTAMP: #{@handoff_timestamp}\n\n"

      @handoff_data.each do |key, value|
        message += "#{key.to_s.upcase}: #{format_handoff_value(value)}\n"
      end

      message
    end

    ##
    # Get handoff chain for circular handoff detection
    #
    # @return [Array<String>] Chain of agents in handoff history
    #
    def handoff_chain
      @handoff_chain ||= []
    end

    ##
    # Add handoff to chain and detect circular patterns
    #
    # @param from_agent [String] Source agent
    # @param to_agent [String] Target agent
    # @return [Boolean] True if handoff is valid (not circular)
    #
    def add_handoff(from_agent, _to_agent)
      @handoff_chain ||= []
      @handoff_chain << from_agent

      # Reset chain if it gets too long
      @handoff_chain.shift if @handoff_chain.length > 10

      true
    end

    ##
    # Set current agent
    #
    # @param agent_name [String] Name of current agent
    #

    private

    def format_handoff_value(value)
      case value
      when Array
        value.map { |v| v.is_a?(Hash) ? v.to_json : v.to_s }.join(", ")
      when Hash
        value.to_json
      else
        value.to_s
      end
    end

    # Removed log_info since Logger module is included

  end

end
