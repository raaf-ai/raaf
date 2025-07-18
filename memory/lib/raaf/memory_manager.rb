# frozen_string_literal: true

require_relative "memory"

module RAAF
  module Memory
    ##
    # Manages memory context and token limits for agents
    #
    # The MemoryManager helps agents work within token limits by intelligently
    # selecting, formatting, and summarizing memories. It provides strategies
    # for pruning old or less relevant memories and can build context strings
    # that fit within model constraints.
    #
    # Key features:
    # - Token-aware memory selection
    # - Automatic pruning when limits are exceeded
    # - Memory summarization capabilities
    # - Flexible formatting options
    #
    # @example Basic usage
    #   manager = MemoryManager.new(max_tokens: 1000)
    #   memories = store.get_recent(20)
    #   context = manager.build_context(memories)
    #
    # @example With custom token counter
    #   require 'tiktoken'
    #   encoder = Tiktoken.encoding_for_model("gpt-4")
    #   
    #   manager = MemoryManager.new(
    #     max_tokens: 2000,
    #     token_counter: ->(text) { encoder.encode(text).length }
    #   )
    #
    # @example Pruning strategies
    #   pruned = manager.prune_memories(memories, :oldest)
    #
    class MemoryManager
      # Default maximum tokens for memory context
      DEFAULT_MAX_TOKENS = 2000
      # Threshold for triggering summarization (80% of max)
      DEFAULT_SUMMARY_THRESHOLD = 0.8

      # @!attribute [r] max_tokens
      #   @return [Integer] Maximum tokens allowed in context
      # @!attribute [r] summary_threshold
      #   @return [Float] Threshold ratio for triggering summarization
      # @!attribute [rw] token_counter
      #   @return [Proc] Function for counting tokens in text
      attr_reader :max_tokens, :summary_threshold
      attr_accessor :token_counter

      ##
      # Initialize a memory manager
      #
      # @param max_tokens [Integer] Maximum tokens for memory context
      # @param summary_threshold [Float] Ratio of max_tokens to trigger summarization
      # @param token_counter [Proc, nil] Custom token counting function
      #
      def initialize(max_tokens: DEFAULT_MAX_TOKENS, summary_threshold: DEFAULT_SUMMARY_THRESHOLD, token_counter: nil)
        @max_tokens = max_tokens
        @summary_threshold = summary_threshold
        @token_counter = token_counter || default_token_counter
      end

      ##
      # Build context from memories within token limit
      #
      # Constructs a formatted context string from the provided memories,
      # ensuring it stays within the token limit. Memories are sorted by
      # recency and added until the limit is approached.
      #
      # @param memories [Array<Hash>] Array of memory hashes
      # @param include_metadata [Boolean] Whether to include metadata in context
      #
      # @return [String] Formatted context within token limit
      #
      # @example Build context for agent
      #   memories = store.search("user preferences", limit: 50)
      #   context = manager.build_context(memories)
      #   # => "## Memory Context\n\n[2024-01-15T...] User prefers dark theme\n---\n..."
      #
      def build_context(memories, include_metadata: false)
        return "" if memories.empty?

        context_parts = []
        total_tokens = 0

        # Sort memories by relevance/recency (most recent first)
        sorted_memories = memories.sort_by { |m| -Time.parse(m[:created_at]).to_i }

        sorted_memories.each do |memory|
          memory_text = format_memory(memory, include_metadata)
          memory_tokens = count_tokens(memory_text)

          # Check if adding this memory would exceed limit
          # If we're over threshold, try to summarize
          if (total_tokens + memory_tokens > @max_tokens) && (total_tokens.to_f / @max_tokens > @summary_threshold)
            break # Stop adding memories
          end

          context_parts << memory_text
          total_tokens += memory_tokens
        end

        # Join memories with proper formatting
        context = "## Memory Context\n\n"
        context += context_parts.join("\n---\n")
        context
      end

      ##
      # Format a single memory for inclusion in context
      #
      # Converts a memory hash into a human-readable string format
      # suitable for inclusion in agent context.
      #
      # @param memory [Hash] Memory hash
      # @param include_metadata [Boolean] Whether to include metadata
      #
      # @return [String] Formatted memory text
      #
      # @example
      #   formatted = manager.format_memory(memory, true)
      #   # => "[2024-01-15T10:30:00Z] (Conv: abc12345) User likes jazz [category: music, verified: true]"
      #
      def format_memory(memory, include_metadata = false)
        parts = []

        # Add timestamp
        timestamp = memory[:created_at]
        parts << "[#{timestamp}]"

        # Add conversation ID if present
        parts << "(Conv: #{memory[:conversation_id].slice(0, 8)})" if memory[:conversation_id]

        # Add content
        parts << memory[:content]

        # Add metadata if requested
        if include_metadata && memory[:metadata] && !memory[:metadata].empty?
          metadata_str = memory[:metadata].map { |k, v| "#{k}: #{v}" }.join(", ")
          parts << "[#{metadata_str}]"
        end

        parts.join(" ")
      end

      ##
      # Count tokens in text
      #
      # Uses the configured token counter to estimate the number of
      # tokens in the given text. Defaults to a simple word-based
      # estimation if no custom counter is provided.
      #
      # @param text [String] Text to count tokens for
      #
      # @return [Integer] Estimated token count
      #
      def count_tokens(text)
        @token_counter.call(text)
      end

      ##
      # Prune memories to fit within token limit
      #
      # Removes memories according to the specified strategy until
      # the remaining memories fit within the token limit.
      #
      # @param memories [Array<Hash>] Array of memory hashes
      # @param strategy [Symbol] Pruning strategy (:oldest, :least_relevant)
      #
      # @return [Array<Hash>] Pruned array of memories
      #
      # @example Remove oldest memories first
      #   pruned = manager.prune_memories(all_memories, :oldest)
      #
      def prune_memories(memories, strategy = :oldest)
        return memories if memories.empty?

        total_tokens = memories.sum { |m| count_tokens(format_memory(m)) }
        return memories if total_tokens <= @max_tokens

        case strategy
        when :oldest
          prune_oldest(memories)
        when :least_relevant
          prune_least_relevant(memories)
        else
          prune_oldest(memories)
        end
      end

      ##
      # Summarize memories that exceed token limit
      #
      # Groups memories by conversation or time period and creates
      # summary memories using the provided summarizer function.
      # Useful for maintaining context while reducing token usage.
      #
      # @param memories [Array<Hash>] Array of memory hashes
      # @param summarizer [Proc] Function that takes text and returns summary
      #
      # @return [Array<Hash>] Array of summary memories
      #
      # @example With OpenAI summarizer
      #   summarizer = ->(text) {
      #     response = openai_client.chat(
      #       model: "gpt-3.5-turbo",
      #       messages: [{ role: "user", content: "Summarize: #{text}" }]
      #     )
      #     response.dig("choices", 0, "message", "content")
      #   }
      #   
      #   summaries = manager.summarize_memories(old_memories, summarizer)
      #
      def summarize_memories(memories, summarizer)
        return nil if memories.empty?

        # Group memories by conversation or time period
        grouped = group_memories(memories)

        grouped.map do |group_key, group_memories|
          content = group_memories.map { |m| m[:content] }.join("\n")
          summary = summarizer.call(content)

          Memory::Memory.new(
            content: "Summary: #{summary}",
            agent_name: group_memories.first[:agent_name],
            conversation_id: group_key,
            metadata: {
              type: "summary",
              original_count: group_memories.size,
              summarized_at: Time.now.iso8601
            }
          ).to_h
        end
      end

      private

      def default_token_counter
        # Simple word-based estimation (1 word ≈ 1.3 tokens)
        ->(text) { (text.to_s.split.size * 1.3).ceil }
      end

      def prune_oldest(memories)
        sorted = memories.sort_by { |m| Time.parse(m[:created_at]) }
        pruned = []
        total_tokens = 0

        sorted.reverse_each do |memory|
          memory_tokens = count_tokens(format_memory(memory))
          if total_tokens + memory_tokens <= @max_tokens
            pruned.unshift(memory)
            total_tokens += memory_tokens
          end
        end

        pruned
      end

      def prune_least_relevant(memories)
        # For now, treat least relevant as oldest
        # In future, could use embeddings or other relevance scoring
        prune_oldest(memories)
      end

      def group_memories(memories)
        # Group by conversation ID if available, otherwise by day
        memories.group_by do |memory|
          memory[:conversation_id] || Time.parse(memory[:created_at]).strftime("%Y-%m-%d")
        end
      end
    end
  end
end
