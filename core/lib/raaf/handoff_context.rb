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

    attr_reader :current_agent, :target_agent, :handoff_data, :shared_context, :handoff_timestamp

    def initialize(current_agent: nil)
      @current_agent = current_agent
      @target_agent = nil
      @handoff_data = {}
      @shared_context = {}
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
      @handoff_data = {}
      @handoff_timestamp = nil
    end

    ##
    # Get handoff data for target agent
    #
    # @param key [String, Symbol] Specific data key to retrieve
    # @return [Object] Handoff data or specific value
    #
    def get_handoff_data(key = nil)
      key ? @handoff_data[key.to_s] || @handoff_data[key.to_sym] : @handoff_data
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
    def add_handoff(from_agent, to_agent)
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
    def current_agent=(agent_name)
      @current_agent = agent_name
    end

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
