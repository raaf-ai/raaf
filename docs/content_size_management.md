# Content Size Management and Automatic Summarization for OpenAI Agents Ruby

This document describes strategies for managing content size when dealing with large numbers of tool calls and conversations in OpenAI Agents, along with a comprehensive automatic summarization system.

## Table of Contents

1. [Content Size Issues](#content-size-issues)
2. [Management Strategies](#management-strategies)
   - [Context Window Management](#1-context-window-management)
   - [Tool Result Optimization](#2-tool-result-optimization)
   - [Request Batching](#3-request-batching)
   - [Conversation Pruning](#4-conversation-pruning)
3. [Automatic Summarization System](#automatic-summarization-system)
   - [System Architecture](#system-architecture)
   - [Manual Triggers](#manual-triggers)
   - [Automatic Triggers](#automatic-triggers)
   - [Runner Integration](#runner-integration)
4. [Usage Examples](#usage-examples)

## Content Size Issues

When dealing with large numbers of tool calls in OpenAI Agents, several content size issues can arise:

1. **Request Size Limits**: OpenAI has token limits per request (~128k for GPT-4, ~4k for GPT-3.5)
2. **Tool Call Accumulation**: Each tool call adds to the conversation history
3. **Response Payload Growth**: Tool results become part of the context window
4. **Memory Consumption**: Local memory usage grows with conversation length

## Management Strategies

### 1. Context Window Management

#### Strategy: Sliding Window
Keep only the most recent N messages to stay within token limits.

```ruby
class ConversationManager
  def initialize(max_messages: 20)
    @max_messages = max_messages
  end

  def prune_conversation(conversation)
    return conversation if conversation.length <= @max_messages
    
    # Always keep system message and recent messages
    system_msg = conversation.first if conversation.first[:role] == "system"
    recent_messages = conversation.last(@max_messages - 1)
    
    [system_msg, *recent_messages].compact
  end
end

# Usage in runner
conversation = manager.prune_conversation(conversation)
```

#### Strategy: Token-Based Pruning
More precise control using actual token counts.

```ruby
require 'tiktoken_ruby'

class TokenManager
  def initialize(model: "gpt-4o", max_tokens: 100_000)
    @encoder = Tiktoken.get_encoding("cl100k_base")
    @max_tokens = max_tokens
  end

  def count_tokens(text)
    @encoder.encode(text).length
  end

  def prune_by_tokens(conversation)
    total_tokens = 0
    pruned = []
    
    # Process from newest to oldest
    conversation.reverse_each do |msg|
      msg_tokens = count_tokens(msg[:content] || "")
      if total_tokens + msg_tokens <= @max_tokens
        pruned.unshift(msg)
        total_tokens += msg_tokens
      else
        break
      end
    end
    
    pruned
  end
end
```

### 2. Tool Result Optimization

#### Strategy: Result Truncation
Limit the size of tool outputs to prevent bloat.

```ruby
class ToolResultOptimizer
  def initialize(max_length: 2000)
    @max_length = max_length
  end

  def truncate_result(result)
    return result if result.length <= @max_length
    
    truncated = result[0...@max_length]
    "#{truncated}...\n[Result truncated - #{result.length} total chars]"
  end
  
  def optimize_structured_data(data)
    case data
    when Array
      # Limit array size and truncate elements
      limited = data.first(10)
      limited.map { |item| truncate_if_string(item) }
    when Hash
      # Keep only essential keys
      essential_keys = %w[id name title content summary]
      data.slice(*essential_keys).transform_values { |v| truncate_if_string(v) }
    else
      truncate_if_string(data)
    end
  end
  
  private
  
  def truncate_if_string(item)
    item.is_a?(String) ? truncate_result(item) : item
  end
end

# Integration in runner.rb
def format_tool_result(result)
  optimizer = ToolResultOptimizer.new
  
  case result
  when Hash, Array
    optimized = optimizer.optimize_structured_data(result)
    optimized.to_json
  else
    optimizer.truncate_result(result.to_s)
  end
end
```

#### Strategy: Streaming Large Results
For very large datasets, implement streaming responses.

```ruby
class StreamingToolResult
  def initialize(data, chunk_size: 1000)
    @data = data
    @chunk_size = chunk_size
    @position = 0
  end

  def next_chunk
    return nil if @position >= @data.length
    
    chunk = @data[@position...@position + @chunk_size]
    @position += @chunk_size
    chunk
  end

  def has_more?
    @position < @data.length
  end
end

# Usage in tool execution
def execute_large_data_tool(params)
  raw_data = fetch_large_dataset(params)
  
  # Return streaming result instead of full data
  {
    type: "streaming",
    total_size: raw_data.length,
    first_chunk: raw_data[0...1000],
    stream_id: generate_stream_id
  }
end
```

### 3. Request Batching

#### Strategy: Parallel Tool Execution
Execute multiple tools concurrently to reduce latency.

```ruby
require 'async'

class BatchedToolExecutor
  def initialize(max_concurrent: 5)
    @max_concurrent = max_concurrent
    @semaphore = Async::Semaphore.new(@max_concurrent)
  end

  def execute_tools_parallel(tool_calls, agent)
    Async do
      # Execute tools in parallel with concurrency limit
      tasks = tool_calls.map do |tool_call|
        @semaphore.async do
          execute_single_tool(tool_call, agent)
        end
      end
      
      # Wait for all to complete
      results = tasks.map(&:wait)
      results
    end
  end
  
  private
  
  def execute_single_tool(tool_call, agent)
    tool_name = tool_call.dig("function", "name")
    arguments = JSON.parse(tool_call.dig("function", "arguments") || "{}")
    
    begin
      result = agent.execute_tool(tool_name, **arguments.transform_keys(&:to_sym))
      {
        role: "tool",
        tool_call_id: tool_call["id"],
        content: format_tool_result(result)
      }
    rescue => e
      {
        role: "tool", 
        tool_call_id: tool_call["id"],
        content: "Error: #{e.message}"
      }
    end
  end
end

# Integration in runner.rb
def process_tool_calls(tool_calls, agent, conversation, context_wrapper = nil, full_response = nil)
  if tool_calls.length > 1
    # Use parallel execution for multiple tools
    executor = BatchedToolExecutor.new
    results = executor.execute_tools_parallel(tool_calls, agent).wait
    results.each { |result| conversation << result }
  else
    # Single tool - use existing logic
    result = process_single_tool_call(tool_calls.first, agent, context_wrapper, full_response)
    conversation << result
  end
  
  false # Continue conversation
end
```

#### Strategy: Request Queuing
Queue requests to avoid overwhelming the API.

```ruby
class RequestQueue
  def initialize(max_concurrent: 3, rate_limit: 10)
    @queue = Queue.new
    @max_concurrent = max_concurrent
    @rate_limit = rate_limit
    @last_request_time = Time.now
    @active_requests = 0
    @mutex = Mutex.new
  end

  def enqueue_request(request_proc)
    @queue.push(request_proc)
    process_queue
  end

  private

  def process_queue
    @mutex.synchronize do
      return if @active_requests >= @max_concurrent
      return if @queue.empty?
      
      # Rate limiting
      time_since_last = Time.now - @last_request_time
      if time_since_last < (1.0 / @rate_limit)
        sleep((1.0 / @rate_limit) - time_since_last)
      end
      
      @active_requests += 1
      @last_request_time = Time.now
    end
    
    request = @queue.pop
    
    Thread.new do
      begin
        request.call
      ensure
        @mutex.synchronize { @active_requests -= 1 }
        process_queue # Process next request
      end
    end
  end
end

# Usage in provider
class QueuedResponsesProvider < Models::ResponsesProvider
  def initialize(*)
    super
    @queue = RequestQueue.new(max_concurrent: 5, rate_limit: 50)
  end

  def chat_completion(*, **)
    result = nil
    @queue.enqueue_request(proc { result = super })
    
    # Wait for result
    sleep(0.01) while result.nil?
    result
  end
end
```

### 4. Conversation Pruning

#### Strategy: Intelligent Message Removal
Remove older messages while preserving important context.

```ruby
class ConversationPruner
  def initialize(max_tokens: 100_000, preserve_system: true)
    @max_tokens = max_tokens
    @preserve_system = preserve_system
    @encoder = Tiktoken.get_encoding("cl100k_base")
  end

  def prune_conversation(conversation)
    return conversation if within_limits?(conversation)
    
    # Separate system messages and regular conversation
    system_msgs = conversation.select { |msg| msg[:role] == "system" }
    regular_msgs = conversation.reject { |msg| msg[:role] == "system" }
    
    # Apply different pruning strategies
    pruned_regular = apply_pruning_strategy(regular_msgs)
    
    # Combine back
    result = @preserve_system ? system_msgs + pruned_regular : pruned_regular
    
    # Final check - if still too large, aggressive pruning
    result = emergency_prune(result) unless within_limits?(result)
    result
  end

  private

  def within_limits?(conversation)
    total_tokens = conversation.sum { |msg| count_tokens(msg[:content] || "") }
    total_tokens <= @max_tokens
  end

  def apply_pruning_strategy(messages)
    # Strategy 1: Remove older tool calls but keep results
    pruned = remove_old_tool_calls(messages)
    return pruned if within_limits?(pruned)
    
    # Strategy 2: Summarize middle conversations
    pruned = summarize_middle_section(pruned)
    return pruned if within_limits?(pruned)
    
    # Strategy 3: Keep only recent messages
    keep_recent_only(pruned)
  end

  def remove_old_tool_calls(messages)
    # Keep recent 10 messages, remove tool calls from older messages
    recent_threshold = [messages.length - 10, 0].max
    
    messages.map.with_index do |msg, idx|
      if idx < recent_threshold && msg[:tool_calls]
        # Remove tool calls from older messages
        msg.merge(tool_calls: nil)
      else
        msg
      end
    end
  end

  def summarize_middle_section(messages)
    return messages if messages.length <= 20
    
    # Keep first 5 and last 10 messages, summarize middle
    first_msgs = messages.first(5)
    last_msgs = messages.last(10)
    middle_msgs = messages[5...-10]
    
    # Create summary of middle section
    middle_summary = create_summary(middle_msgs)
    summary_msg = {
      role: "system",
      content: "[CONVERSATION SUMMARY] #{middle_summary}"
    }
    
    first_msgs + [summary_msg] + last_msgs
  end

  def create_summary(messages)
    # Simple summary - extract key points
    user_messages = messages.select { |msg| msg[:role] == "user" }
    assistant_messages = messages.select { |msg| msg[:role] == "assistant" }
    
    summary = []
    summary << "#{user_messages.length} user messages covering topics: #{extract_topics(user_messages)}"
    summary << "#{assistant_messages.length} assistant responses with #{count_tool_usage(messages)} tool calls"
    
    summary.join(". ")
  end

  def extract_topics(messages)
    # Simple topic extraction - first few words of each message
    topics = messages.map { |msg| msg[:content]&.split&.first(3)&.join(" ") }
    topics.compact.uniq.join(", ")
  end

  def count_tool_usage(messages)
    messages.sum { |msg| msg[:tool_calls]&.length || 0 }
  end

  def keep_recent_only(messages)
    # Emergency: keep only most recent messages
    target_tokens = @max_tokens * 0.8  # 80% of limit
    
    recent_messages = []
    current_tokens = 0
    
    messages.reverse_each do |msg|
      msg_tokens = count_tokens(msg[:content] || "")
      if current_tokens + msg_tokens <= target_tokens
        recent_messages.unshift(msg)
        current_tokens += msg_tokens
      else
        break
      end
    end
    
    recent_messages
  end

  def emergency_prune(messages)
    # Last resort - keep only essential messages
    essential = messages.select do |msg|
      msg[:role] == "system" || 
      (msg[:role] == "user" && msg[:content]&.length&.> 0) ||
      (msg[:role] == "assistant" && !msg[:tool_calls])
    end
    
    essential.last(10) # Keep only last 10 essential messages
  end

  def count_tokens(text)
    return 0 if text.nil? || text.empty?
    @encoder.encode(text).length
  end
end

# Enhanced runner integration
class Runner
  def initialize(*, **)
    super
    @conversation_pruner = ConversationPruner.new(max_tokens: 120_000)
  end

  def run_with_pruning(messages, config:)
    conversation = messages.dup
    
    # Prune before each API call
    conversation = @conversation_pruner.prune_conversation(conversation)
    
    # Continue with normal flow
    run_with_tracing(conversation, config: config)
  end
end
```

#### Strategy: Conversation Checkpointing
Save conversation state at key points for recovery.

```ruby
class ConversationCheckpointer
  def initialize(checkpoint_interval: 5)
    @checkpoint_interval = checkpoint_interval
    @checkpoints = []
    @turn_count = 0
  end

  def maybe_checkpoint(conversation)
    @turn_count += 1
    
    if @turn_count % @checkpoint_interval == 0
      checkpoint = {
        turn: @turn_count,
        timestamp: Time.now,
        conversation: deep_copy(conversation),
        summary: create_checkpoint_summary(conversation)
      }
      
      @checkpoints << checkpoint
      
      # Keep only last 3 checkpoints
      @checkpoints = @checkpoints.last(3)
    end
  end

  def restore_from_checkpoint(checkpoint_index = -1)
    checkpoint = @checkpoints[checkpoint_index]
    return nil unless checkpoint
    
    {
      conversation: checkpoint[:conversation],
      turn: checkpoint[:turn],
      summary: checkpoint[:summary]
    }
  end

  private

  def deep_copy(obj)
    Marshal.load(Marshal.dump(obj))
  end

  def create_checkpoint_summary(conversation)
    "Checkpoint at turn #{@turn_count}: #{conversation.length} messages"
  end
end
```

## Automatic Summarization System

### System Architecture

```ruby
# lib/openai_agents/summarization/summarizer.rb
module OpenAIAgents
  module Summarization
    class Summarizer
      def initialize(provider: nil, model: "gpt-4o-mini")
        @provider = provider || Models::ResponsesProvider.new
        @model = model
      end

      def summarize(messages, style: :concise, focus: :all)
        prompt = build_summarization_prompt(messages, style, focus)
        
        response = @provider.chat_completion(
          messages: [{ role: "user", content: prompt }],
          model: @model,
          max_tokens: 1000
        )
        
        extract_summary(response)
      end

      private

      def build_summarization_prompt(messages, style, focus)
        conversation_text = messages.map do |msg|
          "#{msg[:role].upcase}: #{msg[:content]}"
        end.join("\n\n")

        style_instruction = case style
        when :concise
          "Provide a concise summary in 2-3 sentences."
        when :detailed
          "Provide a detailed summary with key points and outcomes."
        when :bullet_points
          "Provide a bullet-point summary of key topics and decisions."
        end

        focus_instruction = case focus
        when :decisions
          "Focus on decisions made and actions taken."
        when :topics
          "Focus on main topics discussed."
        when :outcomes
          "Focus on outcomes and results achieved."
        else
          "Cover all important aspects of the conversation."
        end

        <<~PROMPT
          Please summarize the following conversation.
          
          #{style_instruction}
          #{focus_instruction}
          
          Conversation:
          #{conversation_text}
          
          Summary:
        PROMPT
      end

      def extract_summary(response)
        response.dig("choices", 0, "message", "content") || "Summary unavailable"
      end
    end
  end
end
```

### Manual Triggers

```ruby
# lib/openai_agents/summarization/manual_trigger.rb
module OpenAIAgents
  module Summarization
    class ManualTrigger
      def initialize(summarizer: nil)
        @summarizer = summarizer || Summarizer.new
      end

      def summarize_conversation(conversation, options = {})
        # Validate conversation
        return nil if conversation.nil? || conversation.empty?
        
        # Extract options
        style = options[:style] || :concise
        focus = options[:focus] || :all
        preserve_recent = options[:preserve_recent] || 5
        
        # Keep recent messages intact
        recent_messages = conversation.last(preserve_recent)
        messages_to_summarize = conversation[0...-preserve_recent]
        
        return conversation if messages_to_summarize.empty?
        
        # Generate summary
        summary = @summarizer.summarize(messages_to_summarize, style: style, focus: focus)
        
        # Create summary message
        summary_message = {
          role: "system",
          content: "[CONVERSATION SUMMARY - #{Time.now.strftime('%Y-%m-%d %H:%M:%S')}]\n#{summary}",
          metadata: {
            type: "summary",
            original_message_count: messages_to_summarize.length,
            summary_style: style,
            summary_focus: focus
          }
        }
        
        # Combine summary with recent messages
        [summary_message] + recent_messages
      end

      def summarize_by_range(conversation, start_index, end_index, options = {})
        return conversation if start_index >= end_index
        
        before_range = conversation[0...start_index]
        range_to_summarize = conversation[start_index..end_index]
        after_range = conversation[(end_index + 1)..-1]
        
        return conversation if range_to_summarize.empty?
        
        # Generate summary for the range
        summary = @summarizer.summarize(range_to_summarize, 
                                       style: options[:style] || :concise,
                                       focus: options[:focus] || :all)
        
        summary_message = {
          role: "system",
          content: "[PARTIAL SUMMARY - Messages #{start_index}-#{end_index}]\n#{summary}",
          metadata: {
            type: "partial_summary",
            range: [start_index, end_index],
            original_message_count: range_to_summarize.length
          }
        }
        
        before_range + [summary_message] + after_range
      end
    end
  end
end
```

### Automatic Triggers

```ruby
# lib/openai_agents/summarization/automatic_triggers.rb
module OpenAIAgents
  module Summarization
    class AutomaticTriggers
      def initialize(summarizer: nil)
        @summarizer = summarizer || Summarizer.new
        @manual_trigger = ManualTrigger.new(@summarizer)
      end

      # Trigger 1: Token-based threshold
      def token_based_trigger(conversation, max_tokens: 100_000)
        encoder = Tiktoken.get_encoding("cl100k_base")
        
        total_tokens = conversation.sum do |msg|
          encoder.encode(msg[:content] || "").length
        end
        
        if total_tokens > max_tokens
          {
            should_summarize: true,
            reason: "Token limit exceeded",
            total_tokens: total_tokens,
            threshold: max_tokens
          }
        else
          { should_summarize: false, total_tokens: total_tokens }
        end
      end

      # Trigger 2: Message count threshold
      def message_count_trigger(conversation, max_messages: 50)
        if conversation.length > max_messages
          {
            should_summarize: true,
            reason: "Message count exceeded",
            message_count: conversation.length,
            threshold: max_messages
          }
        else
          { should_summarize: false, message_count: conversation.length }
        end
      end

      # Trigger 3: Time-based threshold
      def time_based_trigger(conversation, max_age_hours: 24)
        return { should_summarize: false } if conversation.empty?
        
        oldest_message = conversation.first
        message_time = extract_timestamp(oldest_message)
        
        return { should_summarize: false } unless message_time
        
        age_hours = (Time.now - message_time) / 3600
        
        if age_hours > max_age_hours
          {
            should_summarize: true,
            reason: "Conversation too old",
            age_hours: age_hours.round(2),
            threshold: max_age_hours
          }
        else
          { should_summarize: false, age_hours: age_hours.round(2) }
        end
      end

      # Trigger 4: Topic shift detection
      def topic_shift_trigger(conversation, similarity_threshold: 0.7)
        return { should_summarize: false } if conversation.length < 10
        
        # Analyze last 10 messages vs previous 10
        recent_messages = conversation.last(10)
        previous_messages = conversation[-20...-10] || []
        
        return { should_summarize: false } if previous_messages.empty?
        
        recent_topics = extract_topics(recent_messages)
        previous_topics = extract_topics(previous_messages)
        
        similarity = calculate_topic_similarity(recent_topics, previous_topics)
        
        if similarity < similarity_threshold
          {
            should_summarize: true,
            reason: "Topic shift detected",
            similarity: similarity,
            threshold: similarity_threshold,
            recent_topics: recent_topics,
            previous_topics: previous_topics
          }
        else
          { should_summarize: false, similarity: similarity }
        end
      end

      # Trigger 5: Turn-based threshold
      def turn_based_trigger(conversation, max_turns: 20)
        user_turns = conversation.count { |msg| msg[:role] == "user" }
        
        if user_turns > max_turns
          {
            should_summarize: true,
            reason: "Turn limit exceeded",
            user_turns: user_turns,
            threshold: max_turns
          }
        else
          { should_summarize: false, user_turns: user_turns }
        end
      end

      # Trigger 6: Tool usage intensity
      def tool_usage_trigger(conversation, max_tool_calls: 30)
        tool_calls = conversation.sum do |msg|
          msg[:tool_calls]&.length || 0
        end
        
        if tool_calls > max_tool_calls
          {
            should_summarize: true,
            reason: "Too many tool calls",
            tool_calls: tool_calls,
            threshold: max_tool_calls
          }
        else
          { should_summarize: false, tool_calls: tool_calls }
        end
      end

      # Trigger 7: Memory pressure detection
      def memory_pressure_trigger(conversation, max_memory_mb: 100)
        memory_usage = estimate_memory_usage(conversation)
        
        if memory_usage > max_memory_mb
          {
            should_summarize: true,
            reason: "Memory pressure detected",
            memory_usage_mb: memory_usage,
            threshold: max_memory_mb
          }
        else
          { should_summarize: false, memory_usage_mb: memory_usage }
        end
      end

      # Combined trigger evaluation
      def evaluate_triggers(conversation, config = {})
        triggers = []
        
        # Token-based trigger
        if config[:token_threshold]
          result = token_based_trigger(conversation, max_tokens: config[:token_threshold])
          triggers << result if result[:should_summarize]
        end
        
        # Message count trigger
        if config[:message_threshold]
          result = message_count_trigger(conversation, max_messages: config[:message_threshold])
          triggers << result if result[:should_summarize]
        end
        
        # Time-based trigger
        if config[:time_threshold]
          result = time_based_trigger(conversation, max_age_hours: config[:time_threshold])
          triggers << result if result[:should_summarize]
        end
        
        # Topic shift trigger
        if config[:topic_shift_enabled]
          result = topic_shift_trigger(conversation, similarity_threshold: config[:topic_similarity] || 0.7)
          triggers << result if result[:should_summarize]
        end
        
        # Turn-based trigger
        if config[:turn_threshold]
          result = turn_based_trigger(conversation, max_turns: config[:turn_threshold])
          triggers << result if result[:should_summarize]
        end
        
        # Tool usage trigger
        if config[:tool_threshold]
          result = tool_usage_trigger(conversation, max_tool_calls: config[:tool_threshold])
          triggers << result if result[:should_summarize]
        end
        
        # Memory pressure trigger
        if config[:memory_threshold]
          result = memory_pressure_trigger(conversation, max_memory_mb: config[:memory_threshold])
          triggers << result if result[:should_summarize]
        end
        
        {
          should_summarize: triggers.any?,
          triggered_by: triggers.map { |t| t[:reason] },
          trigger_details: triggers
        }
      end

      # Auto-summarize with trigger evaluation
      def auto_summarize_if_needed(conversation, config = {})
        evaluation = evaluate_triggers(conversation, config)
        
        return conversation unless evaluation[:should_summarize]
        
        # Choose summarization strategy based on trigger
        primary_trigger = evaluation[:trigger_details].first
        
        case primary_trigger[:reason]
        when "Token limit exceeded", "Memory pressure detected"
          # Aggressive summarization
          @manual_trigger.summarize_conversation(conversation, 
                                               style: :concise, 
                                               preserve_recent: 3)
        when "Message count exceeded", "Turn limit exceeded"
          # Moderate summarization
          @manual_trigger.summarize_conversation(conversation, 
                                               style: :bullet_points, 
                                               preserve_recent: 5)
        when "Topic shift detected"
          # Summarize older topics, keep recent shift
          @manual_trigger.summarize_conversation(conversation, 
                                               style: :detailed, 
                                               focus: :topics,
                                               preserve_recent: 10)
        when "Too many tool calls"
          # Focus on tool outcomes
          @manual_trigger.summarize_conversation(conversation, 
                                               style: :detailed, 
                                               focus: :outcomes,
                                               preserve_recent: 5)
        else
          # Default summarization
          @manual_trigger.summarize_conversation(conversation, 
                                               style: :concise, 
                                               preserve_recent: 5)
        end
      end

      private

      def extract_timestamp(message)
        # Look for timestamp in metadata first
        timestamp = message.dig(:metadata, :timestamp)
        return Time.parse(timestamp) if timestamp
        
        # Fallback to current time if no timestamp
        Time.now
      rescue
        Time.now
      end

      def extract_topics(messages)
        # Simple topic extraction using key phrases
        text = messages.map { |msg| msg[:content] }.join(" ")
        
        # Basic keyword extraction (in real implementation, use NLP)
        words = text.downcase.scan(/\b\w{4,}\b/)
        words.group_by(&:itself).transform_values(&:count)
             .sort_by { |_, count| -count }
             .first(10)
             .map(&:first)
      end

      def calculate_topic_similarity(topics1, topics2)
        return 0.0 if topics1.empty? || topics2.empty?
        
        # Simple Jaccard similarity
        intersection = (topics1 & topics2).size
        union = (topics1 | topics2).size
        
        intersection.to_f / union
      end

      def estimate_memory_usage(conversation)
        # Rough estimate: 1 character ≈ 1 byte
        total_chars = conversation.sum { |msg| msg[:content]&.length || 0 }
        (total_chars / 1024.0 / 1024.0).round(2) # Convert to MB
      end
    end
  end
end
```

### Configuration

```ruby
# lib/openai_agents/summarization/config.rb
module OpenAIAgents
  module Summarization
    class Config
      attr_accessor :token_threshold, :message_threshold, :time_threshold,
                    :topic_shift_enabled, :topic_similarity, :turn_threshold,
                    :tool_threshold, :memory_threshold, :auto_summarize_enabled

      def initialize
        # Default configuration
        @token_threshold = 100_000
        @message_threshold = 50
        @time_threshold = 24 # hours
        @topic_shift_enabled = true
        @topic_similarity = 0.7
        @turn_threshold = 20
        @tool_threshold = 30
        @memory_threshold = 100 # MB
        @auto_summarize_enabled = true
      end

      def to_h
        {
          token_threshold: @token_threshold,
          message_threshold: @message_threshold,
          time_threshold: @time_threshold,
          topic_shift_enabled: @topic_shift_enabled,
          topic_similarity: @topic_similarity,
          turn_threshold: @turn_threshold,
          tool_threshold: @tool_threshold,
          memory_threshold: @memory_threshold
        }
      end
    end
  end
end
```

### Runner Integration

```ruby
# Enhanced lib/openai_agents/runner.rb integration
class Runner
  def initialize(agent:, provider: nil, tracer: nil, disabled_tracing: false, 
                 stop_checker: nil, summarization_config: nil)
    @agent = agent
    @provider = provider || Models::ResponsesProvider.new
    @disabled_tracing = disabled_tracing || ENV["OPENAI_AGENTS_DISABLE_TRACING"] == "true"
    @tracer = tracer || (@disabled_tracing ? nil : OpenAIAgents.tracer)
    @stop_checker = stop_checker
    
    # Initialize summarization
    @summarization_config = summarization_config || Summarization::Config.new
    @auto_triggers = Summarization::AutomaticTriggers.new if @summarization_config.auto_summarize_enabled
  end

  def run_with_auto_summarization(messages, config:)
    conversation = messages.dup
    
    # Check if auto-summarization is needed before processing
    if @auto_triggers && @summarization_config.auto_summarize_enabled
      evaluation = @auto_triggers.evaluate_triggers(conversation, @summarization_config.to_h)
      
      if evaluation[:should_summarize]
        puts "[Runner] Auto-summarization triggered: #{evaluation[:triggered_by].join(', ')}"
        
        # Apply auto-summarization
        conversation = @auto_triggers.auto_summarize_if_needed(conversation, @summarization_config.to_h)
        
        # Log summarization event
        if @tracer && !@disabled_tracing
          @tracer.add_event("auto_summarization", attributes: {
            "summarization.triggered_by" => evaluation[:triggered_by],
            "summarization.original_message_count" => messages.length,
            "summarization.final_message_count" => conversation.length
          })
        end
      end
    end
    
    # Continue with normal processing
    run_with_tracing(conversation, config: config)
  end

  # Enhanced run method with optional auto-summarization
  def run(messages, stream: false, config: nil, auto_summarize: nil, **kwargs)
    # ... existing run method logic ...
    
    # Check if auto-summarization should be used
    use_auto_summarization = auto_summarize.nil? ? 
                           @summarization_config&.auto_summarize_enabled : 
                           auto_summarize
    
    if use_auto_summarization
      return run_with_auto_summarization(messages, config: final_config)
    end
    
    # ... rest of existing run method ...
  end
end
```

### Agent Enhancement

```ruby
# Enhancement to lib/openai_agents/agent.rb
class Agent
  def summarize_conversation(conversation, **options)
    summarizer = OpenAIAgents::Summarization::ManualTrigger.new
    summarizer.summarize_conversation(conversation, options)
  end

  def summarize_range(conversation, start_index, end_index, **options)
    summarizer = OpenAIAgents::Summarization::ManualTrigger.new
    summarizer.summarize_by_range(conversation, start_index, end_index, options)
  end
end
```

## Usage Examples

### 1. Manual Summarization

```ruby
agent = OpenAIAgents::Agent.new(name: "Assistant", model: "gpt-4o")
runner = OpenAIAgents::Runner.new(agent: agent)

# Summarize manually
conversation = [
  { role: "user", content: "Tell me about Ruby" },
  { role: "assistant", content: "Ruby is a programming language..." },
  # ... more messages
]

summarized = agent.summarize_conversation(conversation, style: :detailed, focus: :topics)
```

### 2. Automatic Summarization Configuration

```ruby
summarization_config = OpenAIAgents::Summarization::Config.new
summarization_config.token_threshold = 80_000
summarization_config.message_threshold = 30
summarization_config.auto_summarize_enabled = true

runner = OpenAIAgents::Runner.new(
  agent: agent,
  summarization_config: summarization_config
)

# This will automatically summarize when thresholds are met
result = runner.run("Start a long conversation...")
```

### 3. Trigger-Specific Summarization

```ruby
triggers = OpenAIAgents::Summarization::AutomaticTriggers.new
evaluation = triggers.evaluate_triggers(conversation, {
  token_threshold: 50_000,
  message_threshold: 25,
  topic_shift_enabled: true
})

if evaluation[:should_summarize]
  puts "Triggers: #{evaluation[:triggered_by]}"
  summarized = triggers.auto_summarize_if_needed(conversation)
end
```

### 4. Manual Trigger with Options

```ruby
manual_trigger = OpenAIAgents::Summarization::ManualTrigger.new
summarized = manual_trigger.summarize_conversation(conversation, {
  style: :bullet_points,
  focus: :decisions,
  preserve_recent: 8
})
```

## Automatic Trigger Strategies

1. **Token-based**: Trigger when conversation exceeds token limit
2. **Message count**: Trigger after N messages
3. **Time-based**: Trigger for conversations older than X hours
4. **Topic shift**: Trigger when conversation topic changes significantly
5. **Turn-based**: Trigger after N user turns
6. **Tool usage**: Trigger when too many tool calls accumulate
7. **Memory pressure**: Trigger when memory usage is high

## Summary

These strategies help manage content size in OpenAI Agents Ruby:

- **Context Window Management**: Use sliding windows, token-based pruning, and conversation summarization to stay within API limits
- **Tool Result Optimization**: Truncate large outputs, stream big datasets, and optimize structured data before sending
- **Request Batching**: Execute tools in parallel, implement request queuing, and use concurrency controls to improve performance
- **Conversation Pruning**: Remove old tool calls, summarize middle sections, create checkpoints, and implement emergency pruning for oversized conversations
- **Automatic Summarization**: Provides both manual control and intelligent automatic triggers, with configurable thresholds and summarization strategies tailored to different scenarios

The Ruby implementation in `runner.rb:304-366` already shows some of these patterns, particularly around `max_turns` handling and the Responses API's continuation mechanism with `previous_response_id`.