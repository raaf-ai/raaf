# frozen_string_literal: true

module OpenAIAgents
  module Handoffs
    ##
    # AdvancedHandoff - Sophisticated handoff logic with filtering and custom prompting
    #
    # Provides advanced handoff capabilities including conditional handoffs based on
    # context analysis, custom handoff prompts, handoff filtering, and intelligent
    # agent selection. Supports complex multi-agent workflows with dynamic routing.
    #
    # == Features
    #
    # * Context-aware handoff decisions
    # * Custom handoff prompts and reasoning
    # * Handoff filtering based on conditions
    # * Agent capability matching
    # * Handoff history and analytics
    # * Dynamic handoff routing
    # * Handoff validation and safety checks
    #
    # == Basic Usage
    #
    #   # Create handoff manager
    #   handoff_manager = OpenAIAgents::Handoffs::AdvancedHandoff.new
    #
    #   # Add agents with capabilities
    #   handoff_manager.add_agent(support_agent, capabilities: [:customer_service, :billing])
    #   handoff_manager.add_agent(tech_agent, capabilities: [:technical_support, :troubleshooting])
    #
    #   # Execute intelligent handoff
    #   result = handoff_manager.execute_handoff(
    #     from_agent: current_agent,
    #     context: conversation_context,
    #     reason: "Customer needs technical help"
    #   )
    #
    # == Advanced Filtering
    #
    #   # Add handoff filters
    #   handoff_manager.add_filter do |from_agent, to_agent, context|
    #     # Only allow handoffs during business hours
    #     business_hours?
    #   end
    #
    #   handoff_manager.add_filter(:capability_check) do |from_agent, to_agent, context|
    #     to_agent.has_capability?(context[:required_capability])
    #   end
    #
    # == Custom Handoff Prompts
    #
    #   # Set custom handoff prompt
    #   handoff_manager.set_handoff_prompt do |from_agent, to_agent, context|
    #     "Please hand off this conversation to #{to_agent.name} because " \
    #     "they specialize in #{context[:topic]}. Here's the context: #{context[:summary]}"
    #   end
    #
    # @author OpenAI Agents Ruby Team
    # @since 0.1.0
    class AdvancedHandoff
      attr_reader :agents, :filters, :history, :handoff_prompt

      ##
      # Creates a new AdvancedHandoff manager
      #
      # @param max_handoffs [Integer] maximum handoffs per conversation (default: 5)
      # @param enable_analytics [Boolean] whether to track handoff analytics (default: true)
      #
      # @example Create handoff manager
      #   manager = OpenAIAgents::Handoffs::AdvancedHandoff.new(max_handoffs: 3)
      def initialize(max_handoffs: 5, enable_analytics: true)
        @agents = {}
        @filters = {}
        @history = []
        @max_handoffs = max_handoffs
        @enable_analytics = enable_analytics
        @handoff_prompt = nil
        @capability_matcher = CapabilityMatcher.new
        @context_analyzer = ContextAnalyzer.new
      end

      ##
      # Adds an agent to the handoff system
      #
      # @param agent [Agent] agent to add
      # @param capabilities [Array<Symbol>] agent capabilities for matching
      # @param priority [Integer] agent priority for selection (higher = more preferred)
      # @param conditions [Hash] conditions for when this agent can be selected
      # @return [void]
      #
      # @example Add agent with capabilities
      #   manager.add_agent(
      #     support_agent,
      #     capabilities: [:customer_service, :billing, :refunds],
      #     priority: 8,
      #     conditions: { business_hours: true }
      #   )
      def add_agent(agent, capabilities: [], priority: 5, conditions: {})
        @agents[agent.name] = {
          agent: agent,
          capabilities: capabilities,
          priority: priority,
          conditions: conditions,
          handoff_count: 0,
          success_rate: 1.0
        }
      end

      ##
      # Removes an agent from the handoff system
      #
      # @param agent_name [String] name of agent to remove
      # @return [Boolean] true if agent was removed
      #
      # @example Remove agent
      #   manager.remove_agent("SupportAgent")
      def remove_agent(agent_name)
        !!@agents.delete(agent_name)
      end

      ##
      # Adds a handoff filter
      #
      # @param name [Symbol] filter name (optional)
      # @yield [Agent, Agent, Hash] filter block that returns true/false
      # @return [void]
      #
      # @example Add named filter
      #   manager.add_filter(:business_hours) do |from, to, context|
      #     Time.now.hour.between?(9, 17)
      #   end
      #
      # @example Add anonymous filter
      #   manager.add_filter do |from, to, context|
      #     context[:conversation_length] < 50
      #   end
      def add_filter(name = nil, &block)
        filter_name = name || "filter_#{@filters.length}"
        @filters[filter_name] = block
      end

      ##
      # Removes a handoff filter
      #
      # @param name [Symbol] filter name
      # @return [Boolean] true if filter was removed
      def remove_filter(name)
        !!@filters.delete(name)
      end

      ##
      # Sets custom handoff prompt generator
      #
      # @yield [Agent, Agent, Hash] block that generates handoff prompt
      # @return [void]
      #
      # @example Set custom prompt
      #   manager.set_handoff_prompt do |from, to, context|
      #     "Transferring from #{from.name} to #{to.name}. " \
      #     "Reason: #{context[:handoff_reason]}"
      #   end
      def set_handoff_prompt(&block)
        @handoff_prompt = block
      end

      ##
      # Executes an intelligent handoff
      #
      # @param from_agent [Agent] current agent
      # @param context [Hash] conversation context
      # @param reason [String] reason for handoff
      # @param target_agent [String, nil] specific target agent (optional)
      # @return [HandoffResult] result of handoff operation
      #
      # @example Execute automatic handoff
      #   result = manager.execute_handoff(
      #     from_agent: current_agent,
      #     context: {
      #       messages: conversation,
      #       topic: "technical_issue",
      #       user_sentiment: "frustrated"
      #     },
      #     reason: "Customer needs technical assistance"
      #   )
      #
      # @example Execute targeted handoff
      #   result = manager.execute_handoff(
      #     from_agent: sales_agent,
      #     target_agent: "TechnicalSupport",
      #     context: context,
      #     reason: "Complex technical question"
      #   )
      def execute_handoff(from_agent:, context:, reason:, target_agent: nil)
        # Validate handoff limits
        conversation_handoffs = count_conversation_handoffs(context)
        if conversation_handoffs >= @max_handoffs
          return HandoffResult.failure(
            from_agent: from_agent.name,
            to_agent: target_agent,
            error: "Maximum handoffs (#{@max_handoffs}) exceeded",
            reason: reason
          )
        end

        # Find target agent
        if target_agent
          to_agent_info = @agents[target_agent]
          unless to_agent_info
            return HandoffResult.failure(
              from_agent: from_agent.name,
              to_agent: target_agent,
              error: "Target agent '#{target_agent}' not found",
              reason: reason
            )
          end
          to_agent = to_agent_info[:agent]
        else
          to_agent = find_best_agent(from_agent, context, reason)
          unless to_agent
            return HandoffResult.failure(
              from_agent: from_agent.name,
              to_agent: nil,
              error: "No suitable agent found for handoff",
              reason: reason
            )
          end
        end

        # Validate handoff with filters
        unless validate_handoff(from_agent, to_agent, context)
          return HandoffResult.failure(
            from_agent: from_agent.name,
            to_agent: to_agent.name,
            error: "Handoff blocked by filters",
            reason: reason
          )
        end

        # Generate handoff data
        handoff_data = generate_handoff_data(from_agent, to_agent, context, reason)

        # Record handoff
        record_handoff(from_agent, to_agent, context, reason, true)

        # Update analytics
        update_analytics(from_agent, to_agent, true) if @enable_analytics

        HandoffResult.success(
          from_agent: from_agent.name,
          to_agent: to_agent.name,
          reason: reason,
          handoff_data: handoff_data
        )
      end

      ##
      # Finds the best agent for handoff based on context
      #
      # @param from_agent [Agent] current agent
      # @param context [Hash] conversation context
      # @param reason [String] handoff reason
      # @return [Agent, nil] best matching agent or nil
      #
      # @example Find best agent
      #   best_agent = manager.find_best_agent(
      #     current_agent,
      #     { topic: "billing", urgency: "high" },
      #     "Customer billing inquiry"
      #   )
      def find_best_agent(from_agent, context, reason)
        # Analyze context to determine required capabilities
        required_capabilities = @context_analyzer.analyze_context(context, reason)

        # Score all eligible agents
        eligible_agents = @agents.values.reject { |info| info[:agent] == from_agent }

        scored_agents = eligible_agents.map do |agent_info|
          score = calculate_agent_score(agent_info, required_capabilities, context)
          { agent_info: agent_info, score: score }
        end

        # Sort by score and return best match
        best_match = scored_agents
                     .select { |item| item[:score].positive? }
                     .min_by { |item| -item[:score] }

        best_match ? best_match[:agent_info][:agent] : nil
      end

      ##
      # Gets handoff analytics and statistics
      #
      # @return [Hash] handoff analytics data
      #
      # @example Get analytics
      #   analytics = manager.analytics
      #   puts "Total handoffs: #{analytics[:total_handoffs]}"
      #   puts "Success rate: #{analytics[:success_rate]}%"
      def analytics
        return {} unless @enable_analytics

        total_handoffs = @history.length
        successful_handoffs = @history.count { |h| h[:successful] }

        {
          total_handoffs: total_handoffs,
          successful_handoffs: successful_handoffs,
          success_rate: total_handoffs.positive? ? (successful_handoffs.to_f / total_handoffs * 100).round(2) : 0,
          most_common_reasons: most_common_handoff_reasons,
          agent_handoff_counts: agent_handoff_counts,
          average_handoffs_per_conversation: average_handoffs_per_conversation
        }
      end

      ##
      # Gets handoff history
      #
      # @param limit [Integer] maximum number of entries to return
      # @return [Array<Hash>] handoff history entries
      #
      # @example Get recent handoffs
      #   recent = manager.get_history(10)
      #   recent.each { |h| puts "#{h[:from_agent]} -> #{h[:to_agent]}: #{h[:reason]}" }
      def get_history(limit = 50)
        @history.last(limit)
      end

      ##
      # Validates if a handoff is allowed
      #
      # @param from_agent [Agent] source agent
      # @param to_agent [Agent] target agent
      # @param context [Hash] conversation context
      # @return [Boolean] true if handoff is allowed
      def validate_handoff(from_agent, to_agent, context)
        @filters.all? do |name, filter|
          filter.call(from_agent, to_agent, context)
        rescue StandardError => e
          warn "Handoff filter '#{name}' failed: #{e.message}"
          false
        end
      end

      ##
      # Clears handoff history
      #
      # @return [void]
      def clear_history
        @history.clear
        @agents.each_value { |info| info[:handoff_count] = 0 }
      end

      private

      def count_conversation_handoffs(context)
        conversation_id = context[:conversation_id] || context[:session_id]
        return 0 unless conversation_id

        @history.count { |h| h[:conversation_id] == conversation_id }
      end

      def calculate_agent_score(agent_info, required_capabilities, context)
        score = 0
        agent_info[:agent]
        capabilities = agent_info[:capabilities]

        # Capability matching score (0-50 points)
        capability_score = @capability_matcher.calculate_match_score(capabilities, required_capabilities)
        score += capability_score * 50

        # Priority score (0-20 points)
        priority_score = agent_info[:priority] / 10.0
        score += priority_score * 20

        # Success rate score (0-20 points)
        success_rate_score = agent_info[:success_rate]
        score += success_rate_score * 20

        # Load balancing score (0-10 points)
        handoff_count = agent_info[:handoff_count]
        max_handoffs = @agents.values.map { |info| info[:handoff_count] }.max || 1
        load_score = 1 - (handoff_count.to_f / max_handoffs)
        score += load_score * 10

        # Condition validation (binary: 0 or maintain current score)
        conditions_met = validate_agent_conditions(agent_info, context)
        score = 0 unless conditions_met

        score
      end

      def validate_agent_conditions(agent_info, context)
        conditions = agent_info[:conditions]
        return true if conditions.empty?

        conditions.all? do |condition, expected_value|
          case condition
          when :business_hours
            expected_value ? business_hours? : !business_hours?
          when :min_conversation_length
            conversation_length(context) >= expected_value
          when :max_conversation_length
            conversation_length(context) <= expected_value
          when :user_tier
            context[:user_tier] == expected_value
          else
            # Custom condition validation
            context[condition] == expected_value
          end
        end
      end

      def business_hours?
        current_hour = Time.now.hour
        current_hour.between?(9, 17) && ![0, 6].include?(Time.now.wday)
      end

      def conversation_length(context)
        context[:messages]&.length || 0
      end

      def generate_handoff_data(from_agent, to_agent, context, reason)
        handoff_data = {
          handoff_reason: reason,
          context_summary: @context_analyzer.summarize_context(context),
          from_agent_capabilities: @agents[from_agent.name][:capabilities],
          to_agent_capabilities: @agents[to_agent.name][:capabilities],
          handoff_timestamp: Time.now.utc.iso8601
        }

        if @handoff_prompt
          handoff_data[:custom_prompt] = @handoff_prompt.call(from_agent, to_agent, context)
        else
          handoff_data[:default_prompt] = generate_default_handoff_prompt(from_agent, to_agent, reason)
        end

        handoff_data
      end

      def generate_default_handoff_prompt(_from_agent, to_agent, reason)
        "I'm transferring this conversation to #{to_agent.name} who is better equipped to help you. " \
          "Reason: #{reason}. #{to_agent.name} will continue from here."
      end

      def record_handoff(from_agent, to_agent, context, reason, successful)
        @history << {
          from_agent: from_agent.name,
          to_agent: to_agent.name,
          reason: reason,
          successful: successful,
          timestamp: Time.now.utc,
          conversation_id: context[:conversation_id] || context[:session_id],
          context_summary: @context_analyzer.summarize_context(context)
        }
      end

      def update_analytics(_from_agent, to_agent, successful)
        # Update handoff counts
        @agents[to_agent.name][:handoff_count] += 1

        # Update success rates (simple exponential moving average)
        agent_info = @agents[to_agent.name]
        current_rate = agent_info[:success_rate]
        alpha = 0.1 # Learning rate
        new_rate = (alpha * (successful ? 1.0 : 0.0)) + ((1 - alpha) * current_rate)
        agent_info[:success_rate] = new_rate
      end

      def most_common_handoff_reasons
        reason_counts = Hash.new(0)
        @history.each { |h| reason_counts[h[:reason]] += 1 }
        reason_counts.sort_by { |_, count| -count }.first(5).to_h
      end

      def agent_handoff_counts
        @agents.transform_values { |info| info[:handoff_count] }
      end

      def average_handoffs_per_conversation
        conversations = @history.group_by { |h| h[:conversation_id] }.keys.compact
        return 0 if conversations.empty?

        (@history.length.to_f / conversations.length).round(2)
      end
    end

    ##
    # CapabilityMatcher - Matches required capabilities with agent capabilities
    class CapabilityMatcher
      ##
      # Calculates match score between required and available capabilities
      #
      # @param available [Array<Symbol>] available capabilities
      # @param required [Array<Symbol>] required capabilities
      # @return [Float] match score between 0.0 and 1.0
      def calculate_match_score(available, required)
        return 1.0 if required.empty?
        return 0.0 if available.empty?

        matched = (available & required).length
        matched.to_f / required.length
      end
    end

    ##
    # ContextAnalyzer - Analyzes conversation context for handoff decisions
    class ContextAnalyzer
      ##
      # Analyzes context to determine required capabilities
      #
      # @param context [Hash] conversation context
      # @param reason [String] handoff reason
      # @return [Array<Symbol>] required capabilities
      def analyze_context(context, reason)
        capabilities = []

        # Analyze based on reason
        capabilities.concat(analyze_reason(reason))

        # Analyze based on conversation content
        capabilities.concat(analyze_messages(context[:messages])) if context[:messages]

        # Analyze based on explicit context
        capabilities.concat(analyze_topic(context[:topic])) if context[:topic]

        capabilities.uniq
      end

      ##
      # Summarizes context for handoff data
      #
      # @param context [Hash] conversation context
      # @return [String] context summary
      def summarize_context(context)
        summary_parts = []

        if context[:messages]
          message_count = context[:messages].length
          summary_parts << "#{message_count} messages"
        end

        summary_parts << "Topic: #{context[:topic]}" if context[:topic]

        summary_parts << "Sentiment: #{context[:user_sentiment]}" if context[:user_sentiment]

        summary_parts << "Urgency: #{context[:urgency]}" if context[:urgency]

        summary_parts.join(", ")
      end

      private

      def analyze_reason(reason)
        reason_lower = reason.downcase
        capabilities = []

        case reason_lower
        when /technical|bug|error|issue/
          capabilities << :technical_support
        when /billing|payment|refund|charge/
          capabilities << :billing_support
        when /account|login|password/
          capabilities << :account_management
        when /sales|purchase|pricing/
          capabilities << :sales_support
        when /cancel|subscription/
          capabilities << :retention
        end

        capabilities
      end

      def analyze_messages(messages)
        capabilities = []
        content = messages.map { |m| m[:content] }.join(" ").downcase

        # Look for technical keywords
        capabilities << :technical_support if content.match?(/error|bug|broken|not working|crash/)

        # Look for billing keywords
        capabilities << :billing_support if content.match?(/bill|payment|charge|refund|money/)

        # Look for account keywords
        capabilities << :account_management if content.match?(/account|login|password|profile/)

        capabilities
      end

      def analyze_topic(topic)
        case topic.to_s.downcase
        when /technical/
          [:technical_support]
        when /billing/
          [:billing_support]
        when /account/
          [:account_management]
        when /sales/
          [:sales_support]
        else
          []
        end
      end
    end
  end
end
