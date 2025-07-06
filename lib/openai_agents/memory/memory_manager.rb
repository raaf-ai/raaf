# frozen_string_literal: true

require_relative "memory"

module OpenAIAgents
  module Memory
    # Manages memory context and token limits for agents
    class MemoryManager
      DEFAULT_MAX_TOKENS = 2000
      DEFAULT_SUMMARY_THRESHOLD = 0.8 # Summarize when 80% full

      attr_reader :max_tokens, :summary_threshold
      attr_accessor :token_counter

      def initialize(max_tokens: DEFAULT_MAX_TOKENS, summary_threshold: DEFAULT_SUMMARY_THRESHOLD, token_counter: nil)
        @max_tokens = max_tokens
        @summary_threshold = summary_threshold
        @token_counter = token_counter || default_token_counter
      end

      # Build context from memories within token limit
      # @param memories [Array<Hash>] Array of memory hashes
      # @param include_metadata [Boolean] Whether to include metadata in context
      # @return [String] Formatted context within token limit
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
          if total_tokens + memory_tokens > @max_tokens
            # If we're over threshold, try to summarize
            if total_tokens.to_f / @max_tokens > @summary_threshold
              break # Stop adding memories
            end
          end

          context_parts << memory_text
          total_tokens += memory_tokens
        end

        # Join memories with proper formatting
        context = "## Memory Context\n\n"
        context += context_parts.join("\n---\n")
        context
      end

      # Format a single memory for inclusion in context
      # @param memory [Hash] Memory hash
      # @param include_metadata [Boolean] Whether to include metadata
      # @return [String] Formatted memory text
      def format_memory(memory, include_metadata = false)
        parts = []
        
        # Add timestamp
        timestamp = memory[:created_at]
        parts << "[#{timestamp}]"

        # Add conversation ID if present
        if memory[:conversation_id]
          parts << "(Conv: #{memory[:conversation_id].slice(0, 8)})"
        end

        # Add content
        parts << memory[:content]

        # Add metadata if requested
        if include_metadata && memory[:metadata] && !memory[:metadata].empty?
          metadata_str = memory[:metadata].map { |k, v| "#{k}: #{v}" }.join(", ")
          parts << "[#{metadata_str}]"
        end

        parts.join(" ")
      end

      # Count tokens in text
      # @param text [String] Text to count tokens for
      # @return [Integer] Estimated token count
      def count_tokens(text)
        @token_counter.call(text)
      end

      # Prune memories to fit within token limit
      # @param memories [Array<Hash>] Array of memory hashes
      # @param strategy [Symbol] Pruning strategy (:oldest, :least_relevant)
      # @return [Array<Hash>] Pruned array of memories
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

      # Summarize memories that exceed token limit
      # @param memories [Array<Hash>] Array of memory hashes
      # @param summarizer [Proc] Function to summarize text
      # @return [Hash] Summary memory
      def summarize_memories(memories, summarizer)
        return nil if memories.empty?

        # Group memories by conversation or time period
        grouped = group_memories(memories)
        
        summaries = grouped.map do |group_key, group_memories|
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

        summaries
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
          if memory[:conversation_id]
            memory[:conversation_id]
          else
            Time.parse(memory[:created_at]).strftime("%Y-%m-%d")
          end
        end
      end
    end
  end
end