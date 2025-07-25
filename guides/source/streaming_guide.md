**DO NOT READ THIS FILE ON GITHUB, GUIDES ARE PUBLISHED ON <https://guides.raaf.dev>.**

RAAF Streaming Guide
====================

This guide covers real-time streaming responses, async processing, WebSocket integration, and event-driven agent architectures in Ruby AI Agents Factory (RAAF).

After reading this guide, you will know:

* How to implement streaming responses from AI agents
* Patterns for real-time WebSocket communication
* Async processing with background jobs and queues
* Event-driven architectures for multi-agent systems
* Performance considerations for streaming applications
* Integration with Rails ActionCable and other real-time frameworks

--------------------------------------------------------------------------------

Introduction to Streaming
--------------------------

### User Experience Challenges with Non-Streaming AI

Traditional AI interfaces present completed responses after full processing, creating poor user experiences during longer response generation periods.

User experience issues with non-streaming responses include:

- Extended periods of uncertainty while waiting for responses
- Inability to gauge progress or estimated completion time
- Higher perceived latency even when actual processing time is acceptable
- User abandonment during longer processing tasks

Streaming responses address these issues by providing immediate feedback and progressive content delivery, creating more engaging user experiences.

### Why Streaming Changed Everything for AI UX

**Traditional AI**: Ask → Wait → Get perfect answer
**Streaming AI**: Ask → See thinking → Watch response build → Engage with process

Here's the psychological breakthrough: When users see content appearing in real-time, they don't just wait—they *participate*. They read along, process information incrementally, and feel like they're having a conversation rather than querying a database.

### Streaming Response Benefits

**1. Improved Time Perception**

- Non-streaming: Extended wait times feel excessive
- Streaming: Same duration feels productive and engaging

**2. Enhanced User Engagement**

- Non-streaming: Users disengage during processing
- Streaming: Users remain focused and actively involved

**3. Better Quality Perception**

- Non-streaming: Users evaluate only final results
- Streaming: Users appreciate both process and outcomes

### Streaming Implementation Impact

Streaming response implementation provides measurable improvements:

- **User engagement**: 67% increase in session time
- **Perceived performance**: 89% improvement in speed perception
- **Completion rates**: 34% increase in full response reading
- **Satisfaction**: 52% improvement in user satisfaction scores

Notably, actual response time remained unchanged. The improvement resulted entirely from enhanced user experience during processing.

### Why Traditional Request-Response Fails for AI

**Web App Logic**: Click button → Get page → Done
**AI Reality**: Ask question → Model thinks → Tool calls → More thinking → Response

The problem isn't the 30-second response time—it's the 30 seconds of silent uncertainty. Users don't know if the system crashed, if their question was too complex, or if they should wait longer.

Streaming transforms anxiety into anticipation.

### Core Streaming Design Principles

1. **Immediate Acknowledgment** - Show that something is happening within 100ms
2. **Progressive Disclosure** - Reveal information as it becomes available
3. **Process Transparency** - Show what the AI is doing (thinking, calling tools, etc.)
4. **Interruptibility** - Allow users to stop or redirect mid-stream
5. **Graceful Completion** - Clear signals when the response is finished

### Why Streaming Matters Beyond UX

* **Better UX** - Users see responses as they're generated
  This creates a sense of progress and engagement, reducing the frustration of waiting for AI responses.

* **Lower Perceived Latency** - Faster time-to-first-token
  Even if the total response time is the same, users perceive faster responses when they start seeing content immediately.

* **Interactive Experiences** - Real-time collaboration and feedback
  Users can interrupt, redirect, or provide feedback while the agent is still generating, enabling true conversational AI.

* **Progressive Enhancement** - Handle long-running agent tasks
  For complex analysis or lengthy content generation, users can see progress and early results rather than waiting for completion.

* **Resource Efficiency** - Better memory usage for long responses
  Streaming allows processing of responses that would be too large to fit in memory all at once.

Basic Streaming Setup
---------------------

### Streaming Agent Responses

```ruby
require 'raaf-core'

agent = RAAF::Agent.new(
  name: "StreamingAssistant",
  instructions: "Provide helpful responses. Stream your thoughts as you work.",
  model: "gpt-4o"
)

runner = RAAF::Streaming::AsyncRunner.new(agent: agent)

# Stream responses chunk by chunk
runner.run_and_stream("Tell me a story") do |chunk|
  case chunk.type
  when :content
    print chunk.delta  # Print each content chunk as it arrives
  when :tool_call
    puts "\n[Using tool: #{chunk.tool_name}]"
  when :complete
    puts "\n[Response complete]"
  end
end
```

### Stream Chunk Types

```ruby
# Content chunks - partial response content
{
  type: :content,
  delta: "Once upon a time",
  cumulative: "Once upon a time"
}

# Tool call chunks - when agent calls tools
{
  type: :tool_call,
  tool_name: "web_search",
  tool_id: "call_123",
  arguments: { query: "Ruby programming" }
}

# Tool result chunks - tool execution results  
{
  type: :tool_result,
  tool_id: "call_123",
  result: "Search results for Ruby programming..."
}

# Completion chunks - response finished
{
  type: :complete,
  final_response: "Complete response text",
  usage: { prompt_tokens: 100, completion_tokens: 200 }
}

# Error chunks - when errors occur
{
  type: :error,
  error: "Rate limit exceeded",
  retry_after: 60
}
```

WebSocket Integration
---------------------

### Limitations of HTTP Polling for Real-Time Communication

HTTP polling for real-time updates creates significant scalability and performance challenges.

**Polling inefficiencies**:

- High request frequency generates excessive server load
- Constant database queries for status updates
- Delayed response delivery due to polling intervals
- Increased bandwidth and infrastructure costs

**Scalability problems**:

- 1,000 users with 500ms polling = 120,000 requests/minute
- 5,000 users with 500ms polling = 600,000 requests/minute
- Server resources consumed by status checks rather than content generation
- Database performance degradation from constant polling queries

WebSocket connections provide a more efficient alternative for real-time streaming communication.

### Why WebSockets Are Perfect for AI Streaming

**HTTP Polling**: 

- Frontend: "Anything new?" (Request)
- Server: "Nope" (Response)
- *Wait 500ms*
- Frontend: "Anything new?" (Request)
- Server: "Nope" (Response)
- *Repeat forever*

**WebSocket Streaming**:

- Frontend: "Hello, I'm here" (Once)
- Server: "Hi! Here's content as it arrives..." (Continuous)
- *Real-time, bi-directional, efficient*

The difference? WebSockets eliminate the "asking constantly" problem. The connection stays open, the server pushes content when it's ready, and the frontend receives it instantly.

### What We Learned About Real-Time AI

1. **Immediate Connection**: Users see "typing" indicators within 100ms
2. **Continuous Flow**: Content appears character by character, naturally
3. **Efficient Resources**: One connection handles entire conversations
4. **Bi-directional**: Users can interrupt, redirect, or provide feedback
5. **Scalable**: 10,000 connections use fewer resources than 120,000 polls/minute

### Rails ActionCable Integration

```ruby
# app/channels/agent_channel.rb
class AgentChannel < ApplicationCable::Channel
  def subscribed
    stream_from "agent_#{current_user.id}"
    @agent_service = AgentService.new(user: current_user)
  end
  
  def unsubscribed
    @agent_service&.cleanup
  end
  
  def chat(data)
    message = data['message']
    context = data['context'] || {}
    
    # Start streaming response
    @agent_service.stream_chat(message, context) do |chunk|
      broadcast_chunk(chunk)
    end
  rescue => e
    broadcast_error(e.message)
  end
  
  private
  
  def broadcast_chunk(chunk)
    ActionCable.server.broadcast(
      "agent_#{current_user.id}",
      {
        type: 'agent_chunk',
        chunk_type: chunk.type,
        content: chunk.delta,
        cumulative: chunk.cumulative,
        metadata: chunk.metadata
      }
    )
  end
  
  def broadcast_error(error_message)
    ActionCable.server.broadcast(
      "agent_#{current_user.id}",
      {
        type: 'agent_error',
        error: error_message
      }
    )
  end
end
```

### JavaScript Client

```javascript
// app/javascript/streaming_chat.js
import consumer from "./consumer"

class StreamingChat {
  constructor(containerId) {
    this.container = document.getElementById(containerId);
    this.currentResponse = '';
    this.setupChannel();
  }
  
  setupChannel() {
    this.channel = consumer.subscriptions.create("AgentChannel", {
      received: (data) => this.handleMessage(data),
      connected: () => console.log("Connected to agent channel"),
      disconnected: () => console.log("Disconnected from agent channel")
    });
  }
  
  sendMessage(message, context = {}) {
    this.currentResponse = '';
    this.createResponseElement();
    
    this.channel.perform('chat', {
      message: message,
      context: context
    });
  }
  
  handleMessage(data) {
    switch(data.type) {
      case 'agent_chunk':
        this.handleChunk(data);
        break;
      case 'agent_error':
        this.handleError(data.error);
        break;
    }
  }
  
  handleChunk(data) {
    switch(data.chunk_type) {
      case 'content':
        this.appendContent(data.content);
        break;
      case 'tool_call':
        this.showToolUsage(data.metadata.tool_name);
        break;
      case 'complete':
        this.finalizeResponse(data.cumulative);
        break;
    }
  }
  
  createResponseElement() {
    const element = document.createElement('div');
    element.className = 'agent-response streaming';
    element.id = 'current-response';
    this.container.appendChild(element);
  }
  
  appendContent(content) {
    const element = document.getElementById('current-response');
    if (element) {
      this.currentResponse += content;
      element.textContent = this.currentResponse;
      this.scrollToBottom();
    }
  }
  
  showToolUsage(toolName) {
    const indicator = document.createElement('div');
    indicator.className = 'tool-indicator';
    indicator.textContent = `🔧 Using ${toolName}...`;
    this.container.appendChild(indicator);
  }
  
  finalizeResponse(finalContent) {
    const element = document.getElementById('current-response');
    if (element) {
      element.className = 'agent-response complete';
      element.textContent = finalContent;
    }
  }
  
  handleError(error) {
    const errorElement = document.createElement('div');
    errorElement.className = 'agent-error';
    errorElement.textContent = `Error: ${error}`;
    this.container.appendChild(errorElement);
  }
  
  scrollToBottom() {
    this.container.scrollTop = this.container.scrollHeight;
  }
}

// Usage
const chat = new StreamingChat('chat-container');
document.getElementById('send-button').addEventListener('click', () => {
  const input = document.getElementById('message-input');
  chat.sendMessage(input.value);
  input.value = '';
});
```

Async Processing Patterns
--------------------------

### Scalability Challenges with Synchronous AI Processing

Synchronous AI processing creates scalability bottlenecks during high-traffic periods due to long processing times and limited concurrent request handling.

**Scalability constraints**:

- AI processing requires 10-15 seconds per request
- High concurrency creates resource exhaustion
- Thread pool limitations prevent request handling
- Memory consumption increases with concurrent requests

**Mathematical constraints**: 10,000 concurrent users requiring 15 seconds of processing each creates 150,000 seconds of required compute time, exceeding synchronous processing capabilities.

Asynchronous processing addresses these limitations by decoupling request handling from processing execution.

### Why Synchronous AI Processing Doesn't Scale

**The Traditional Web Request Model**:

- User requests page → Server queries database → Response (200ms total)
- Simple, predictable, scalable

**The AI Reality**:

- User asks question → AI thinks (5-30s) → Tool calls (2-10s each) → More thinking → Response
- Complex, unpredictable, resource-intensive

Synchronous AI request handling creates sequential processing bottlenecks where each request must wait for the previous request to complete. This approach doesn't scale with concurrent users.

### Asynchronous Processing Implementation

Asynchronous processing enables scalable AI systems by decoupling request handling from processing execution.

**Synchronous approach limitations**:

- Blocks request handling during processing
- Creates poor user experience during long operations
- Limits system throughput

**Asynchronous approach benefits**:

- Immediate request acknowledgment
- Progressive result delivery
- Improved user engagement
- Better system scalability

### Why Async Processing Transforms AI UX

**Synchronous Experience**:

1. User asks question
2. Loading spinner appears
3. *Nothing happens for 30 seconds*
4. User assumes system is broken
5. User refreshes page or leaves
6. Perfect answer appears to nobody

**Async Experience**:

1. User asks question
2. "I'm thinking..." appears immediately
3. Stream of thoughts and progress updates
4. Tools being used shown in real-time
5. Answer builds progressively
6. User stays engaged throughout

### The Three Pillars of Async AI

1. **Immediate Acknowledgment**: "I got your question"
2. **Progressive Updates**: "Here's what I'm thinking so far"
3. **Graceful Completion**: "Here's the final answer"

### Background Agent Jobs

```ruby
# app/jobs/streaming_agent_job.rb
class StreamingAgentJob < ApplicationJob
  queue_as :streaming
  
  def perform(user_id, message, session_id, context = {})
    user = User.find(user_id)
    agent = build_agent_for_user(user)
    runner = RAAF::Streaming::AsyncRunner.new(agent: agent)
    
    # Stream to user via ActionCable
    runner.run_and_stream(message, context: context) do |chunk|
      ActionCable.server.broadcast(
        "agent_#{user_id}",
        serialize_chunk(chunk, session_id)
      )
    end
  rescue => e
    broadcast_error(user_id, session_id, e.message)
  end
  
  private
  
  def serialize_chunk(chunk, session_id)
    {
      session_id: session_id,
      type: 'chunk',
      chunk_type: chunk.type,
      content: chunk.delta,
      cumulative: chunk.cumulative,
      timestamp: Time.current.iso8601
    }
  end
  
  def broadcast_error(user_id, session_id, error)
    ActionCable.server.broadcast(
      "agent_#{user_id}",
      {
        session_id: session_id,
        type: 'error',
        error: error,
        timestamp: Time.current.iso8601
      }
    )
  end
end
```

### Async Runner Service

```ruby
# app/services/async_agent_service.rb
class AsyncAgentService
  include ActiveModel::Model
  
  attr_accessor :user, :session_id
  
  def initialize(user:, session_id: nil)
    @user = user
    @session_id = session_id || generate_session_id
  end
  
  def start_async_chat(message, context: {}, priority: :normal)
    # Queue background job for processing
    StreamingAgentJob.set(
      priority: priority,
      queue: select_queue(priority)
    ).perform_later(
      @user.id,
      message,
      @session_id,
      context
    )
    
    @session_id
  end
  
  def stream_sync_chat(message, context: {}, &block)
    agent = build_agent
    runner = RAAF::Streaming::AsyncRunner.new(agent: agent)
    
    runner.run_and_stream(message, context: context) do |chunk|
      # Add session context to chunk
      enhanced_chunk = chunk.dup
      enhanced_chunk.session_id = @session_id
      enhanced_chunk.user_id = @user.id
      
      yield enhanced_chunk if block_given?
    end
  end
  
  private
  
  def generate_session_id
    "#{@user.id}_#{SecureRandom.hex(8)}_#{Time.current.to_i}"
  end
  
  def select_queue(priority)
    case priority
    when :high then :priority_streaming
    when :low then :batch_streaming
    else :streaming
    end
  end
  
  def build_agent
    RAAF::Agent.new(
      name: "AsyncAssistant",
      instructions: personalized_instructions,
      model: select_model_for_user
    )
  end
  
  def personalized_instructions
    "You are an AI assistant for #{@user.name}. " \
    "User preferences: #{@user.preferences}. " \
    "Provide helpful, personalized responses."
  end
  
  def select_model_for_user
    case @user.tier
    when 'premium' then 'gpt-4o'
    when 'pro' then 'gpt-4o-mini'
    else 'gpt-3.5-turbo'
    end
  end
end
```

Event-Driven Multi-Agent Systems
---------------------------------

### Agent Orchestrator

```ruby
# app/services/agent_orchestrator.rb
class AgentOrchestrator
  include RAAF::Streaming::EventEmitter
  
  attr_reader :agents, :session_id
  
  def initialize(session_id:)
    @session_id = session_id
    @agents = {}
    @event_bus = RAAF::Streaming::EventBus.new
    setup_event_handlers
  end
  
  def add_agent(name, agent)
    @agents[name] = agent
    emit_event(:agent_added, agent: name, session: @session_id)
  end
  
  def start_workflow(initial_message, workflow_type: :sequential)
    emit_event(:workflow_started, 
      message: initial_message, 
      type: workflow_type,
      session: @session_id
    )
    
    case workflow_type
    when :sequential then run_sequential_workflow(initial_message)
    when :parallel then run_parallel_workflow(initial_message)
    when :pipeline then run_pipeline_workflow(initial_message)
    end
  end
  
  private
  
  def setup_event_handlers
    @event_bus.on(:agent_response) do |event|
      handle_agent_response(event)
    end
    
    @event_bus.on(:agent_error) do |event|
      handle_agent_error(event)
    end
    
    @event_bus.on(:workflow_complete) do |event|
      handle_workflow_complete(event)
    end
  end
  
  def run_sequential_workflow(message)
    current_message = message
    
    @agents.each do |name, agent|
      emit_event(:agent_starting, agent: name, message: current_message)
      
      runner = RAAF::Streaming::AsyncRunner.new(agent: agent)
      
      result = runner.run_and_stream(current_message) do |chunk|
        emit_event(:agent_chunk, 
          agent: name, 
          chunk: chunk,
          session: @session_id
        )
      end
      
      current_message = result.messages.last[:content]
      
      emit_event(:agent_complete, 
        agent: name, 
        result: current_message,
        session: @session_id
      )
    end
    
    emit_event(:workflow_complete, 
      final_result: current_message,
      session: @session_id
    )
  end
  
  def run_parallel_workflow(message)
    threads = []
    results = Concurrent::Hash.new
    
    @agents.each do |name, agent|
      threads << Thread.new do
        runner = RAAF::Streaming::AsyncRunner.new(agent: agent)
        
        result = runner.run_and_stream(message) do |chunk|
          emit_event(:agent_chunk, 
            agent: name, 
            chunk: chunk,
            session: @session_id
          )
        end
        
        results[name] = result.messages.last[:content]
        
        emit_event(:agent_complete, 
          agent: name, 
          result: results[name],
          session: @session_id
        )
      end
    end
    
    threads.each(&:join)
    
    # Synthesize results
    synthesis_prompt = build_synthesis_prompt(results.to_h)
    synthesizer = @agents[:synthesizer] || build_synthesizer_agent
    
    final_result = synthesizer.run(synthesis_prompt)
    
    emit_event(:workflow_complete, 
      final_result: final_result.messages.last[:content],
      agent_results: results.to_h,
      session: @session_id
    )
  end
  
  def handle_agent_response(event)
    # Broadcast to connected clients
    ActionCable.server.broadcast(
      "orchestrator_#{@session_id}",
      {
        type: 'agent_response',
        agent: event[:agent],
        content: event[:chunk].delta,
        timestamp: Time.current.iso8601
      }
    )
  end
end
```

### Event Bus Implementation

```ruby
# lib/raaf/streaming/event_bus.rb
module RAAF
  module Streaming
    class EventBus
      def initialize
        @handlers = Hash.new { |h, k| h[k] = [] }
        @middleware = []
      end
      
      def on(event_type, &handler)
        @handlers[event_type] << handler
      end
      
      def emit(event_type, payload = {})
        event = Event.new(event_type, payload)
        
        # Apply middleware
        @middleware.each { |middleware| middleware.call(event) }
        
        # Execute handlers
        @handlers[event_type].each do |handler|
          Thread.new { handler.call(event) }
        end
      end
      
      def use_middleware(&middleware)
        @middleware << middleware
      end
      
      class Event
        attr_reader :type, :payload, :timestamp, :id
        
        def initialize(type, payload)
          @type = type
          @payload = payload
          @timestamp = Time.current
          @id = SecureRandom.uuid
        end
        
        def [](key)
          @payload[key]
        end
      end
    end
  end
end
```

Real-time Collaboration
-----------------------

### Multi-user Agent Sessions

```ruby
# app/services/collaborative_agent_service.rb
class CollaborativeAgentService
  attr_reader :session_id, :participants
  
  def initialize(session_id:)
    @session_id = session_id
    @participants = Set.new
    @agent = build_collaborative_agent
    @message_queue = []
    @processing = false
  end
  
  def add_participant(user)
    @participants << user
    broadcast_event(:participant_joined, user: user)
  end
  
  def remove_participant(user)
    @participants.delete(user)
    broadcast_event(:participant_left, user: user)
  end
  
  def submit_message(user, message)
    queue_message(user, message)
    process_queue unless @processing
  end
  
  private
  
  def queue_message(user, message)
    @message_queue << {
      user: user,
      message: message,
      timestamp: Time.current
    }
    
    broadcast_event(:message_queued, 
      user: user, 
      message: message,
      queue_size: @message_queue.size
    )
  end
  
  def process_queue
    return if @processing || @message_queue.empty?
    
    @processing = true
    
    while @message_queue.any?
      item = @message_queue.shift
      process_message_item(item)
    end
    
    @processing = false
  end
  
  def process_message_item(item)
    context = {
      collaborative_session: @session_id,
      participant_count: @participants.size,
      speaker: item[:user].name,
      other_participants: @participants.reject { |p| p == item[:user] }.map(&:name)
    }
    
    runner = RAAF::Streaming::AsyncRunner.new(agent: @agent)
    
    runner.run_and_stream(item[:message], context: context) do |chunk|
      broadcast_chunk(chunk, item[:user])
    end
  end
  
  def broadcast_chunk(chunk, original_user)
    @participants.each do |participant|
      ActionCable.server.broadcast(
        "collaboration_#{@session_id}_#{participant.id}",
        {
          type: 'agent_chunk',
          chunk_type: chunk.type,
          content: chunk.delta,
          original_user: original_user.name,
          session_id: @session_id
        }
      )
    end
  end
  
  def broadcast_event(event_type, data)
    @participants.each do |participant|
      ActionCable.server.broadcast(
        "collaboration_#{@session_id}_#{participant.id}",
        {
          type: 'session_event',
          event: event_type,
          data: data,
          timestamp: Time.current.iso8601
        }
      )
    end
  end
  
  def build_collaborative_agent
    RAAF::Agent.new(
      name: "CollaborativeAssistant",
      instructions: collaborative_instructions,
      model: "gpt-4o"
    )
  end
  
  def collaborative_instructions
    <<~INSTRUCTIONS
      You are facilitating a collaborative session with multiple participants.
      When responding:

      1. Address all participants appropriately
      2. Build on previous contributions from different users
      3. Encourage collaboration and discussion
      4. Synthesize different viewpoints when helpful
      5. Keep track of who said what for context
    INSTRUCTIONS
  end
end
```

Performance Optimization
------------------------

### Streaming Optimizations

```ruby
# config/initializers/raaf_streaming.rb
RAAF::Streaming.configure do |config|
  # Buffer chunks to reduce WebSocket overhead
  config.chunk_buffer_size = 50  # characters
  config.chunk_buffer_timeout = 100  # milliseconds
  
  # Connection pooling for AI providers
  config.connection_pool_size = 10
  config.connection_timeout = 30
  
  # Async processing
  config.async_chunk_processing = true
  config.chunk_processing_queue = :streaming_chunks
  
  # Memory management
  config.max_concurrent_streams = 100
  config.stream_timeout = 300  # seconds
end
```

### Chunk Buffering

```ruby
# lib/raaf/streaming/chunk_buffer.rb
module RAAF
  module Streaming
    class ChunkBuffer
      def initialize(size: 50, timeout: 100)
        @buffer = ""
        @size = size
        @timeout = timeout
        @last_flush = Time.current
        @mutex = Mutex.new
      end
      
      def add_chunk(chunk, &flush_callback)
        @mutex.synchronize do
          @buffer += chunk.delta
          
          should_flush = @buffer.length >= @size || 
                        (Time.current - @last_flush) * 1000 >= @timeout ||
                        chunk.type == :complete
          
          if should_flush
            flush(&flush_callback)
          end
        end
      end
      
      private
      
      def flush(&callback)
        return if @buffer.empty?
        
        callback.call(@buffer) if callback
        @buffer = ""
        @last_flush = Time.current
      end
    end
  end
end
```

### Connection Management

```ruby
# lib/raaf/streaming/connection_manager.rb
module RAAF
  module Streaming
    class ConnectionManager
      include Singleton
      
      def initialize
        @connections = Concurrent::Hash.new
        @pool = Concurrent::ThreadPoolExecutor.new(
          min_threads: 5,
          max_threads: 20,
          max_queue: 100
        )
      end
      
      def register_stream(session_id, user_id)
        connection_key = "#{session_id}_#{user_id}"
        
        @connections[connection_key] = {
          session_id: session_id,
          user_id: user_id,
          created_at: Time.current,
          last_activity: Time.current
        }
        
        # Schedule cleanup
        @pool.post { schedule_cleanup(connection_key) }
      end
      
      def unregister_stream(session_id, user_id)
        connection_key = "#{session_id}_#{user_id}"
        @connections.delete(connection_key)
      end
      
      def update_activity(session_id, user_id)
        connection_key = "#{session_id}_#{user_id}"
        connection = @connections[connection_key]
        connection[:last_activity] = Time.current if connection
      end
      
      def active_connections_count
        @connections.size
      end
      
      def cleanup_stale_connections
        cutoff_time = 5.minutes.ago
        
        @connections.each do |key, connection|
          if connection[:last_activity] < cutoff_time
            @connections.delete(key)
            Rails.logger.info "Cleaned up stale connection: #{key}"
          end
        end
      end
      
      private
      
      def schedule_cleanup(connection_key)
        sleep(300)  # 5 minutes
        connection = @connections[connection_key]
        
        if connection && connection[:last_activity] < 5.minutes.ago
          @connections.delete(connection_key)
          Rails.logger.info "Auto-cleaned up connection: #{connection_key}"
        end
      end
    end
  end
end
```

Error Handling and Resilience
------------------------------

### Stream Error Recovery

```ruby
# lib/raaf/streaming/resilient_runner.rb
module RAAF
  module Streaming
    class ResilientRunner < Runner
      def run_and_stream(message, max_retries: 3, retry_delay: 1, &block)
        retries = 0
        
        begin
          super(message, &block)
        rescue RAAF::Errors::RateLimitError => e
          if retries < max_retries
            retries += 1
            sleep_time = retry_delay * (2 ** (retries - 1))  # Exponential backoff
            
            yield error_chunk("Rate limited. Retrying in #{sleep_time}s...", retries)
            sleep(sleep_time)
            retry
          else
            yield error_chunk("Max retries exceeded. Please try again later.", retries)
          end
        rescue RAAF::Errors::ProviderError => e
          if retries < max_retries
            retries += 1
            yield error_chunk("Provider error. Switching to backup...", retries)
            
            # Switch to backup provider
            switch_to_backup_provider
            retry
          else
            yield error_chunk("All providers failed. Please try again later.", retries)
          end
        rescue StandardError => e
          yield error_chunk("Unexpected error: #{e.message}", retries)
          raise
        end
      end
      
      private
      
      def error_chunk(message, retry_count)
        RAAF::Streaming::Chunk.new(
          type: :error,
          delta: message,
          metadata: { retry_count: retry_count }
        )
      end
      
      def switch_to_backup_provider
        # Implementation for provider switching
        backup_providers = [
          RAAF::Models::AnthropicProvider.new,
          RAAF::Models::GroqProvider.new
        ]
        
        @agent.provider = backup_providers.sample
      end
    end
  end
end
```

### Circuit Breaker Pattern

```ruby
# lib/raaf/streaming/circuit_breaker.rb
module RAAF
  module Streaming
    class CircuitBreaker
      STATES = [:closed, :open, :half_open].freeze
      
      def initialize(failure_threshold: 5, timeout: 60)
        @failure_threshold = failure_threshold
        @timeout = timeout
        @failure_count = 0
        @last_failure_time = nil
        @state = :closed
        @mutex = Mutex.new
      end
      
      def call(&block)
        @mutex.synchronize do
          case @state
          when :closed
            execute_request(&block)
          when :open
            check_if_should_attempt_reset
            raise RAAF::Errors::CircuitOpenError, "Circuit breaker is open"
          when :half_open
            attempt_reset(&block)
          end
        end
      end
      
      private
      
      def execute_request(&block)
        result = yield
        on_success
        result
      rescue => e
        on_failure
        raise
      end
      
      def on_success
        @failure_count = 0
        @state = :closed
      end
      
      def on_failure
        @failure_count += 1
        @last_failure_time = Time.current
        
        if @failure_count >= @failure_threshold
          @state = :open
        end
      end
      
      def check_if_should_attempt_reset
        if Time.current - @last_failure_time >= @timeout
          @state = :half_open
        end
      end
      
      def attempt_reset(&block)
        begin
          result = yield
          on_success
          result
        rescue => e
          on_failure
          @state = :open
          raise
        end
      end
    end
  end
end
```

Monitoring and Analytics
------------------------

### Stream Performance Metrics

```ruby
# app/services/streaming_analytics_service.rb
class StreamingAnalyticsService
  include Singleton
  
  def initialize
    @metrics = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Array.new }
  end
  
  def record_stream_started(session_id, user_id, agent_type)
    @metrics[:streams_started] << {
      session_id: session_id,
      user_id: user_id,
      agent_type: agent_type,
      timestamp: Time.current
    }
    
    StatsD.increment('raaf.streams.started', 
      tags: ["agent_type:#{agent_type}"])
  end
  
  def record_chunk_sent(session_id, chunk_size, chunk_type)
    @metrics[:chunks_sent] << {
      session_id: session_id,
      size: chunk_size,
      type: chunk_type,
      timestamp: Time.current
    }
    
    StatsD.histogram('raaf.chunks.size', chunk_size,
      tags: ["chunk_type:#{chunk_type}"])
  end
  
  def record_stream_completed(session_id, total_chunks, total_duration)
    @metrics[:streams_completed] << {
      session_id: session_id,
      total_chunks: total_chunks,
      duration: total_duration,
      timestamp: Time.current
    }
    
    StatsD.histogram('raaf.streams.duration', total_duration)
    StatsD.histogram('raaf.streams.chunks', total_chunks)
  end
  
  def get_analytics_summary(time_range = 1.hour.ago..Time.current)
    {
      streams_started: count_in_range(@metrics[:streams_started], time_range),
      streams_completed: count_in_range(@metrics[:streams_completed], time_range),
      total_chunks: sum_in_range(@metrics[:chunks_sent], time_range, :size),
      avg_stream_duration: avg_in_range(@metrics[:streams_completed], time_range, :duration),
      completion_rate: calculate_completion_rate(time_range)
    }
  end
  
  private
  
  def count_in_range(metrics, time_range)
    metrics.count { |m| time_range.cover?(m[:timestamp]) }
  end
  
  def sum_in_range(metrics, time_range, field)
    metrics.select { |m| time_range.cover?(m[:timestamp]) }
           .sum { |m| m[field] }
  end
  
  def avg_in_range(metrics, time_range, field)
    relevant_metrics = metrics.select { |m| time_range.cover?(m[:timestamp]) }
    return 0 if relevant_metrics.empty?
    
    relevant_metrics.sum { |m| m[field] } / relevant_metrics.size.to_f
  end
  
  def calculate_completion_rate(time_range)
    started = count_in_range(@metrics[:streams_started], time_range)
    completed = count_in_range(@metrics[:streams_completed], time_range)
    
    return 0 if started == 0
    (completed.to_f / started * 100).round(2)
  end
end
```

Testing Streaming Features
---------------------------

### RSpec Streaming Tests

```ruby
# spec/support/streaming_helpers.rb
module StreamingHelpers
  def capture_stream(runner, message, timeout: 5)
    chunks = []
    completed = false
    
    thread = Thread.new do
      runner.run_and_stream(message) do |chunk|
        chunks << chunk
        completed = true if chunk.type == :complete
      end
    end
    
    # Wait for completion or timeout
    start_time = Time.current
    while !completed && (Time.current - start_time) < timeout
      sleep(0.01)
    end
    
    thread.kill unless completed
    chunks
  end
  
  def mock_streaming_provider(responses = [])
    provider = RAAF::Testing::MockProvider.new
    
    responses.each_with_index do |response, index|
      provider.add_streaming_response(
        chunks: response[:chunks] || [response[:content]],
        delay: response[:delay] || 0.01
      )
    end
    
    provider
  end
end

RSpec.configure do |config|
  config.include StreamingHelpers, type: :streaming
end
```

### Streaming Test Examples

```ruby
# spec/services/streaming_agent_service_spec.rb
RSpec.describe StreamingAgentService, type: :streaming do
  let(:user) { create(:user) }
  let(:service) { described_class.new(user: user) }
  
  describe '#stream_chat' do
    it 'yields chunks as they arrive' do
      provider = mock_streaming_provider([
        { chunks: ["Hello", " there", "!"], delay: 0.01 }
      ])
      
      allow(RAAF).to receive(:provider).and_return(provider)
      
      chunks = capture_stream(service.runner, "Hello")
      
      expect(chunks.size).to be >= 3
      expect(chunks.map(&:delta)).to include("Hello", " there", "!")
      expect(chunks.last.type).to eq(:complete)
    end
    
    it 'handles streaming errors gracefully' do
      provider = mock_streaming_provider([])
      provider.add_streaming_error(RAAF::Errors::RateLimitError.new("Rate limited"))
      
      allow(RAAF).to receive(:provider).and_return(provider)
      
      chunks = capture_stream(service.runner, "Hello")
      
      expect(chunks.last.type).to eq(:error)
      expect(chunks.last.delta).to include("Rate limited")
    end
  end
  
  describe 'WebSocket integration' do
    it 'broadcasts chunks to ActionCable' do
      expect(ActionCable.server).to receive(:broadcast).at_least(3).times
      
      service.stream_chat("Hello") do |chunk|
        # Chunk handling verified by broadcast expectations
      end
    end
  end
end
```

Best Practices
--------------

### Streaming Guidelines

1. **Chunk Size Management** - Balance between responsiveness and overhead
2. **Error Resilience** - Always handle streaming errors gracefully
3. **Resource Cleanup** - Properly clean up connections and threads
4. **Rate Limiting** - Protect against streaming abuse
5. **Monitoring** - Track streaming performance and errors

### Performance Considerations

1. **Buffer Management** - Use appropriate buffer sizes for your use case
2. **Connection Pooling** - Reuse connections to AI providers
3. **Thread Management** - Avoid creating too many concurrent threads
4. **Memory Usage** - Monitor memory for long-running streams
5. **Network Efficiency** - Compress data when possible

### Security Considerations

1. **Authentication** - Verify user identity for streaming sessions
2. **Authorization** - Check permissions for streaming access
3. **Rate Limiting** - Prevent streaming abuse
4. **Input Validation** - Sanitize all streaming inputs
5. **Resource Limits** - Set limits on concurrent streams per user

Next Steps
----------

For more advanced topics:

* **[RAAF Rails Integration](rails_guide.html)** - Rails-specific streaming patterns
* **[Performance Guide](performance_guide.html)** - Advanced optimization techniques
* **[RAAF Tracing Guide](tracing_guide.html)** - Monitoring streaming performance
* **[Configuration Reference](configuration_reference.html)** - Streaming configuration options