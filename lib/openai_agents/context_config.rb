# frozen_string_literal: true

module OpenAIAgents
  # Configuration for context management strategies
  class ContextConfig
    attr_accessor :enabled, :strategy, :max_tokens, :max_messages,
                  :preserve_system, :preserve_recent, :summarization_enabled,
                  :summarization_threshold, :summarization_model

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

    # Factory methods for common configurations

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

    def self.balanced(model: "gpt-4o")
      new.tap do |config|
        config.strategy = :token_sliding_window
        # Uses model defaults (set in ContextManager)
        config.preserve_recent = 5
      end
    end

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

    def self.message_based(max_messages: 30)
      new.tap do |config|
        config.strategy = :message_count
        config.max_messages = max_messages
        config.preserve_recent = 5
      end
    end

    def self.with_summarization(model: "gpt-4o")
      new.tap do |config|
        config.strategy = :summarization
        config.summarization_enabled = true
        config.summarization_threshold = 0.7
        config.preserve_recent = 5
      end
    end

    def self.disabled
      new.tap do |config|
        config.enabled = false
      end
    end

    # Create appropriate context manager based on config
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
