# frozen_string_literal: true

module RAAF

  ##
  # Manages handoff state and data transfer between agents
  #
  # This class provides explicit control over agent handoffs, replacing
  # the implicit hook-based system with direct function calling approach.
  #
  class HandoffContext

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
      @handoff_timestamp = Time.current
      @shared_context.merge!(data)

      log_info("Handoff prepared", {
                 from: @current_agent,
                 to: @target_agent,
                 reason: reason,
                 data_keys: data.keys
               })

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
      @current_agent = @target_agent
      @target_agent = nil

      log_info("Handoff executed", {
                 from: previous_agent,
                 to: @current_agent,
                 timestamp: @handoff_timestamp
               })

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

    def log_info(message, data = {})
      if defined?(RAAF::Logger)
        RAAF::Logger.info(message, data)
      else
        puts "[HandoffContext] #{message}: #{data}"
      end
    end

  end

end
