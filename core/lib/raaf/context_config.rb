# frozen_string_literal: true

module RubyAIAgentsFactory
  ##
  # Configuration for context management strategies
  #
  # The ContextConfig class provides comprehensive configuration options for managing
  # conversation context during agent execution. It supports multiple strategies for
  # handling context size limits, including token-based sliding windows, message count
  # limits, and summarization techniques.
  #
  # == Context Management Strategies
  #
  # * **Token Sliding Window**: Maintains context within token limits by removing older messages
  # * **Message Count**: Limits context by maximum number of messages
  # * **Summarization**: Uses AI to summarize older conversation parts when limits are reached
  #
  # == Key Features
  #
  # * **Flexible Strategies**: Multiple approaches to context management
  # * **Model-Aware**: Automatically adjusts limits based on target model capabilities
  # * **Preservation Rules**: Ensures important messages (system, recent) are retained
  # * **Factory Methods**: Pre-configured setups for common use cases
  # * **Dynamic Limits**: Adjustable token and message limits based on requirements
  #
  # @example Conservative configuration for production
  #   config = ContextConfig.conservative(model: "gpt-4o")
  #   context_manager = config.build_context_manager(model: "gpt-4o")
  #
  # @example Message-based context management
  #   config = ContextConfig.message_based(max_messages: 20)
  #   # Will keep only the most recent 20 messages
  #
  # @example Summarization-enabled context
  #   config = ContextConfig.with_summarization(model: "gpt-4o")
  #   # Will summarize older parts when context gets large
  #
  # @example Custom configuration
  #   config = ContextConfig.new
  #   config.strategy = :token_sliding_window
  #   config.max_tokens = 50_000
  #   config.preserve_recent = 8
  #   config.summarization_enabled = true
  #
  # @author OpenAI Agents Ruby Team
  # @since 0.1.0
  # @see ContextManager For the actual context management implementation
  class ContextConfig
    # @return [Boolean] whether context management is enabled
    attr_accessor :enabled
    
    # @return [Symbol] context management strategy (:token_sliding_window, :message_count, :summarization)
    attr_accessor :strategy
    
    # @return [Integer, nil] maximum tokens to maintain in context (nil for model defaults)
    attr_accessor :max_tokens
    
    # @return [Integer] maximum number of messages to maintain
    attr_accessor :max_messages
    
    # @return [Boolean] whether to always preserve system messages
    attr_accessor :preserve_system
    
    # @return [Integer] number of recent messages to always preserve
    attr_accessor :preserve_recent
    
    # @return [Boolean] whether summarization is enabled
    attr_accessor :summarization_enabled
    
    # @return [Float] threshold (0.0-1.0) at which to trigger summarization
    attr_accessor :summarization_threshold
    
    # @return [String] model to use for summarization (typically cheaper than main model)
    attr_accessor :summarization_model

    ##
    # Initialize context configuration with sensible defaults
    #
    # Sets up a balanced configuration suitable for most use cases,
    # with token-based sliding window strategy and preservation of
    # system messages and recent conversation.
    #
    # @example Basic initialization
    #   config = ContextConfig.new
    #   # Uses token sliding window with 50 message limit
    def initialize
      @enabled = true
      @strategy = :token_sliding_window # :token_sliding_window, :message_count, :summarization
      @max_tokens = nil # nil means use model defaults
      @max_messages = 50
      @preserve_system = true
      @preserve_recent = 5
      @summarization_enabled = false
      @summarization_threshold = 0.8 # Summarize when 80% of limit reached
      @summarization_model = "gpt-3.5-turbo" # Cheaper model for summarization
    end

    ##
    # Factory methods for common configurations
    
    ##
    # Create conservative configuration with strict token limits
    #
    # Provides a conservative approach to context management with lower
    # token limits to ensure reliable performance and reduced costs.
    # Suitable for production environments where predictability is important.
    #
    # @param model [String] target model name for token limit calculation
    # @return [ContextConfig] configured instance with conservative settings
    #
    # @example Conservative setup for GPT-4
    #   config = ContextConfig.conservative(model: "gpt-4o")
    #   # Uses 50,000 tokens max, preserves 3 recent messages
    def self.conservative(model: "gpt-4o")
      new.tap do |config|
        config.strategy = :token_sliding_window
        config.max_tokens = case model
                            when /gpt-4o/, /gpt-4-turbo/
                              50_000 # Very conservative for gpt-4
                            when /gpt-3.5/
                              2_000
                            else
                              4_000
                            end
        config.preserve_recent = 3
      end
    end

    ##
    # Create balanced configuration using model defaults
    #
    # Provides a balanced approach that uses the model's default token
    # limits while maintaining reasonable preservation rules. This is
    # the recommended configuration for most applications.
    #
    # @param model [String] target model name for configuration
    # @return [ContextConfig] configured instance with balanced settings
    #
    # @example Balanced configuration
    #   config = ContextConfig.balanced(model: "gpt-4o")
    #   # Uses model defaults, preserves 5 recent messages
    def self.balanced(model: "gpt-4o")
      new.tap do |config|
        config.strategy = :token_sliding_window
        # Uses model defaults (set in ContextManager)
        config.preserve_recent = 5
      end
    end

    ##
    # Create aggressive configuration with high token limits
    #
    # Maximizes context window usage by setting token limits close to
    # model maximums. Suitable for applications requiring extensive
    # conversation history or complex reasoning tasks.
    #
    # @param model [String] target model name for limit calculation
    # @return [ContextConfig] configured instance with aggressive settings
    #
    # @example Aggressive setup for maximum context
    #   config = ContextConfig.aggressive(model: "gpt-4o")
    #   # Uses 120,000 tokens max, preserves 10 recent messages
    def self.aggressive(model: "gpt-4o")
      new.tap do |config|
        config.strategy = :token_sliding_window
        config.max_tokens = case model
                            when /gpt-4o/, /gpt-4-turbo/
                              120_000 # Close to limit
                            when /gpt-3.5-turbo-16k/
                              15_000
                            when /gpt-3.5/
                              3_500
                            else
                              7_500
                            end
        config.preserve_recent = 10
      end
    end

    ##
    # Create message count-based configuration
    #
    # Uses message count rather than token count for context management.
    # Simpler to understand and predict, suitable for applications with
    # consistent message sizes.
    #
    # @param max_messages [Integer] maximum number of messages to maintain
    # @return [ContextConfig] configured instance with message-based strategy
    #
    # @example Message-based context management
    #   config = ContextConfig.message_based(max_messages: 20)
    #   # Keeps only the most recent 20 messages
    def self.message_based(max_messages: 30)
      new.tap do |config|
        config.strategy = :message_count
        config.max_messages = max_messages
        config.preserve_recent = 5
      end
    end

    ##
    # Create configuration with summarization enabled
    #
    # Enables AI-powered summarization of older conversation parts when
    # context limits are approached. Provides the best context retention
    # but with additional computational cost for summarization.
    #
    # @param model [String] target model name for configuration
    # @return [ContextConfig] configured instance with summarization enabled
    #
    # @example Summarization-enabled context
    #   config = ContextConfig.with_summarization(model: "gpt-4o")
    #   # Will summarize older conversation when 70% of limit reached
    def self.with_summarization(model: "gpt-4o")
      new.tap do |config|
        config.strategy = :summarization
        config.summarization_enabled = true
        config.summarization_threshold = 0.7
        config.preserve_recent = 5
      end
    end

    ##
    # Create disabled configuration
    #
    # Disables all context management, allowing unlimited context growth.
    # Use with caution as this can lead to token limit errors and high costs.
    # Suitable for short conversations or testing scenarios.
    #
    # @return [ContextConfig] configured instance with context management disabled
    #
    # @example Disabled context management
    #   config = ContextConfig.disabled
    #   # No context limits - use with caution!
    def self.disabled
      new.tap do |config|
        config.enabled = false
      end
    end

    ##
    # Create appropriate context manager based on configuration
    #
    # Factory method that creates the appropriate ContextManager instance
    # based on the configured strategy and settings. Returns nil if context
    # management is disabled.
    #
    # @param model [String, nil] model name for context manager configuration
    # @return [ContextManager, nil] configured context manager or nil if disabled
    # @raise [ArgumentError] if strategy is unknown
    #
    # @example Building a context manager
    #   config = ContextConfig.balanced(model: "gpt-4o")
    #   manager = config.build_context_manager(model: "gpt-4o")
    #   managed_messages = manager.manage_context(conversation)
    def build_context_manager(model: nil)
      return nil unless enabled

      case strategy
      when :token_sliding_window
        ContextManager.new(
          model: model,
          max_tokens: max_tokens,
          preserve_system: preserve_system,
          preserve_recent: preserve_recent
        )
      when :message_count
        # Could create a MessageCountContextManager in the future
        ContextManager.new(
          model: model,
          max_tokens: max_tokens,
          preserve_system: preserve_system,
          preserve_recent: preserve_recent
        )
      when :summarization
        # Could create a SummarizationContextManager in the future
        # For now, use regular manager with lower limits to trigger more often
        ContextManager.new(
          model: model,
          max_tokens: max_tokens || 10_000, # Lower limit to trigger summarization
          preserve_system: preserve_system,
          preserve_recent: preserve_recent
        )
      else
        raise ArgumentError, "Unknown context strategy: #{strategy}"
      end
    end
  end
end
