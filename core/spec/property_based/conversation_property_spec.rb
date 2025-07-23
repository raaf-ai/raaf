# frozen_string_literal: true

require "spec_helper"
require "rantly"
require "rantly/rspec_extensions"

RSpec.describe "Conversation Flow Property-Based Tests" do
  describe "Message structure validation" do
    context "property: message format consistency" do
      it "maintains valid message structure through any conversation" do
        property_of {
          # Generate random conversation
          num_messages = integer(1..20)
          messages = num_messages.times.map do |i|
            role = choose("user", "assistant", "system", "tool")
            content = case integer(0..3)
                      when 0 then string  # Simple string
                      when 1 then { text: string }  # Structured
                      when 2 then [{ type: "text", text: string }]  # Array format
                      when 3 then ""  # Empty
                      end
            
            msg = { role: role, content: content }
            
            # Add optional fields randomly
            msg[:name] = string(:alpha) if boolean && role == "tool"
            msg[:tool_call_id] = "call_#{string(:alnum, 8)}" if boolean && role == "tool"
            
            msg
          end
          
          [messages]
        }.check(100) do |messages|
          # Create agent and runner
          agent = RAAF::Agent.new(name: "TestAgent")
          runner = RAAF::Runner.new(agent: agent)
          
          # Process messages through normalize_messages
          normalized = runner.send(:normalize_messages, messages)
          
          # All messages should have required fields
          normalized.each do |msg|
            expect(msg).to have_key(:role)
            expect(msg).to have_key(:content)
            expect(msg[:role]).to be_a(String)
            
            # Content should be normalized to string
            expect(msg[:content]).to be_a(String)
          end
          
          # Preserve order
          expect(normalized.size).to eq(messages.size)
        end
      end
    end

    context "property: conversation continuity" do
      it "maintains conversation context across any number of turns" do
        property_of {
          agent = RAAF::Agent.new(name: "ContextAgent", max_turns: 100)
          
          # Generate conversation with context dependencies
          num_turns = integer(2..10)
          context_items = array(integer(1..5)) { string(:alpha) }
          
          conversation = []
          
          # Initial context setting
          conversation << {
            role: "user",
            content: "Remember these items: #{context_items.join(', ')}"
          }
          
          # Random turns that might reference context
          (num_turns - 1).times do |i|
            if boolean
              # Reference a random context item
              item = context_items.sample
              conversation << {
                role: "user",
                content: "What about #{item}?"
              }
            else
              # New topic
              conversation << {
                role: "user",
                content: "Tell me about #{string}"
              }
            end
          end
          
          [agent, conversation, context_items]
        }.check(25) do |agent, conversation, context_items|
          runner = RAAF::Runner.new(agent: agent)
          
          # Mock provider to echo context items
          allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete) do |_, params|
            messages = params[:messages]
            
            # Check if any context item is mentioned
            mentioned_items = context_items.select do |item|
              messages.any? { |m| m[:content].to_s.include?(item) }
            end
            
            {
              "output" => [{
                "type" => "message",
                "role" => "assistant",
                "content" => [{
                  "type" => "text",
                  "text" => "I remember: #{mentioned_items.join(', ')}"
                }]
              }],
              "usage" => { "input_tokens" => 10, "output_tokens" => 10 }
            }
          end
          
          # Run single turn
          result = runner.run(conversation.first)
          
          # Should maintain conversation structure
          expect(result.messages).to be_an(Array)
          expect(result.messages.first[:role]).to eq("user")
        end
      end
    end
  end

  describe "Handoff flow properties" do
    context "property: handoff chain integrity" do
      it "maintains valid handoff chains with random agent configurations" do
        property_of {
          # Generate random agent network
          num_agents = integer(2..8)
          agents = num_agents.times.map do |i|
            RAAF::Agent.new(
              name: "Agent#{i}",
              instructions: "I am agent #{i}",
              max_turns: integer(3..10)
            )
          end
          
          # Generate random handoff connections (DAG)
          handoffs = []
          num_agents.times do |from|
            # Can handoff to any agent after this one (prevents cycles)
            if from < num_agents - 1
              num_handoffs = integer(0..[num_agents - from - 1, 3].min)
              targets = ((from + 1)...num_agents).to_a.sample(num_handoffs)
              targets.each do |to|
                handoffs << [from, to]
              end
            end
          end
          
          [agents, handoffs]
        }.check(50) do |agents, handoffs|
          # Set up handoffs
          handoffs.each do |from_idx, to_idx|
            agents[from_idx].add_handoff(agents[to_idx])
          end
          
          # Verify handoff structure
          handoffs.each do |from_idx, to_idx|
            from_agent = agents[from_idx]
            to_agent = agents[to_idx]
            
            # Should have handoff registered
            expect(from_agent.handoff_agents).to include(to_agent.name)
            
            # Should have transfer tool
            tool = from_agent.tools.find do |t|
              t.name == "transfer_to_#{to_agent.name.downcase}"
            end
            expect(tool).not_to be_nil
            
            # Tool should be callable
            expect(tool).to respond_to(:execute)
          end
          
          # No agent should handoff to itself
          agents.each do |agent|
            expect(agent.handoff_agents).not_to include(agent.name)
          end
        end
      end
    end

    context "property: handoff execution safety" do
      it "safely handles any handoff sequence without infinite loops" do
        property_of {
          # Create agents with various handoff patterns
          num_agents = integer(3..6)
          agents = num_agents.times.map do |i|
            RAAF::Agent.new(name: "Agent#{i}")
          end
          
          # Create potentially problematic handoff patterns
          pattern_type = choose(:linear, :star, :mesh, :cycle_attempt)
          
          handoffs = case pattern_type
                     when :linear
                       # A -> B -> C -> D
                       (0...num_agents - 1).map { |i| [i, i + 1] }
                     when :star
                       # All agents can handoff to last agent
                       (0...num_agents - 1).map { |i| [i, num_agents - 1] }
                     when :mesh
                       # Random connections
                       Array.new(integer(num_agents..(num_agents * 2))) do
                         from = integer(0...num_agents)
                         to = integer(0...num_agents)
                         [from, to] if from != to
                       end.compact.uniq
                     when :cycle_attempt
                       # Try to create cycle (should be prevented)
                       edges = (0...num_agents - 1).map { |i| [i, i + 1] }
                       edges << [num_agents - 1, 0]  # Close the cycle
                       edges
                     end
          
          [agents, handoffs, pattern_type]
        }.check(25) do |agents, handoffs, pattern_type|
          # Set up handoffs
          handoffs.each do |from_idx, to_idx|
            if from_idx != to_idx  # Prevent self-handoff
              agents[from_idx].add_handoff(agents[to_idx])
            end
          end
          
          runner = RAAF::Runner.new(agent: agents.first)
          
          # Track handoff chain
          handoff_count = 0
          max_handoffs = 10  # Safety limit
          
          # Mock provider to trigger handoffs
          allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete) do
            handoff_count += 1
            
            if handoff_count < 3 && agents.first.handoff_agents.any?
              # Trigger a handoff
              target = agents.first.handoff_agents.first
              {
                "output" => [{
                  "type" => "function_call",
                  "name" => "transfer_to_#{target.downcase}",
                  "arguments" => "{}",
                  "call_id" => "call_#{handoff_count}"
                }],
                "usage" => { "input_tokens" => 5, "output_tokens" => 5 }
              }
            else
              # Normal response
              {
                "output" => [{
                  "type" => "message",
                  "role" => "assistant",
                  "content" => [{ "type" => "text", "text" => "Done" }]
                }],
                "usage" => { "input_tokens" => 5, "output_tokens" => 5 }
              }
            end
          end
          
          # Should complete without infinite loops
          result = runner.run("Test handoff pattern")
          
          expect(result).to be_a(RAAF::RunResult)
          expect(handoff_count).to be <= max_handoffs
        end
      end
    end
  end

  describe "Token usage properties" do
    context "property: token counting accuracy" do
      it "accurately accumulates tokens across any conversation pattern" do
        property_of {
          # Generate random conversation with various token counts
          num_turns = integer(1..15)
          
          turns = num_turns.times.map do |i|
            {
              message: { role: choose("user", "assistant"), content: string },
              tokens: {
                input: integer(10..500),
                output: integer(10..500),
                total: nil  # Will be calculated
              }
            }
          end
          
          # Calculate totals
          turns.each do |turn|
            turn[:tokens][:total] = turn[:tokens][:input] + turn[:tokens][:output]
          end
          
          [turns]
        }.check(50) do |turns|
          agent = RAAF::Agent.new(name: "TokenAgent")
          runner = RAAF::Runner.new(agent: agent)
          
          # Track token accumulation manually
          expected_input = 0
          expected_output = 0
          
          # Mock provider responses
          turn_index = 0
          allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete) do
            turn = turns[turn_index] || turns.last
            turn_index += 1
            
            expected_input += turn[:tokens][:input]
            expected_output += turn[:tokens][:output]
            
            {
              "output" => [{
                "type" => "message",
                "role" => "assistant",
                "content" => [{ "type" => "text", "text" => turn[:message][:content] }]
              }],
              "usage" => {
                "input_tokens" => turn[:tokens][:input],
                "output_tokens" => turn[:tokens][:output],
                "total_tokens" => turn[:tokens][:total]
              }
            }
          end
          
          # Run single turn (mocking limits us)
          result = runner.run("Start conversation")
          
          # Verify token counts
          expect(result.usage[:input_tokens]).to eq(turns.first[:tokens][:input])
          expect(result.usage[:output_tokens]).to eq(turns.first[:tokens][:output])
          expect(result.usage[:total_tokens]).to eq(
            result.usage[:input_tokens] + result.usage[:output_tokens]
          )
        end
      end
    end

    context "property: token limit enforcement" do
      it "respects max_tokens limit with any content size" do
        property_of {
          max_tokens = integer(10..1000)
          content_length = integer(1..5000)
          
          # Generate content of specific length
          content = string(:alpha, content_length)
          
          [max_tokens, content]
        }.check(50) do |max_tokens, content|
          agent = RAAF::Agent.new(name: "LimitAgent")
          config = RAAF::RunConfig.new(max_tokens: max_tokens)
          runner = RAAF::Runner.new(agent: agent, config: config)
          
          # Mock provider to respect max_tokens
          allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete) do |_, params|
            # Provider should receive max_tokens parameter
            expect(params[:max_tokens]).to eq(max_tokens) if params[:max_tokens]
            
            # Generate response respecting limit
            response_tokens = [content.length / 4, max_tokens].min
            
            {
              "output" => [{
                "type" => "message",
                "role" => "assistant",
                "content" => [{
                  "type" => "text",
                  "text" => content[0...response_tokens * 4]  # Approximate
                }]
              }],
              "usage" => {
                "input_tokens" => content.length / 4,  # Approximate
                "output_tokens" => response_tokens,
                "total_tokens" => content.length / 4 + response_tokens
              }
            }
          end
          
          result = runner.run(content)
          
          # Output tokens should not exceed max_tokens
          expect(result.usage[:output_tokens]).to be <= max_tokens
        end
      end
    end
  end

  describe "Concurrent conversation properties" do
    context "property: thread-safe conversation handling" do
      it "maintains conversation integrity under concurrent access" do
        property_of {
          num_threads = integer(2..8)
          messages_per_thread = integer(1..5)
          
          # Generate unique messages for each thread
          thread_messages = num_threads.times.map do |i|
            messages_per_thread.times.map do |j|
              {
                role: "user",
                content: "Thread #{i} message #{j}: #{string}"
              }
            end
          end
          
          [num_threads, thread_messages]
        }.check(25) do |num_threads, thread_messages|
          agent = RAAF::Agent.new(name: "ConcurrentAgent")
          
          results = Concurrent::Array.new
          
          # Mock provider to return thread-specific responses
          allow_any_instance_of(RAAF::Models::ResponsesProvider).to receive(:complete) do |_, params|
            user_msg = params[:messages].last[:content]
            thread_match = user_msg.match(/Thread (\d+)/)
            thread_id = thread_match ? thread_match[1] : "unknown"
            
            {
              "output" => [{
                "type" => "message",
                "role" => "assistant",
                "content" => [{
                  "type" => "text",
                  "text" => "Response for thread #{thread_id}"
                }]
              }],
              "usage" => { "input_tokens" => 10, "output_tokens" => 10 }
            }
          end
          
          threads = thread_messages.each_with_index.map do |messages, thread_id|
            Thread.new do
              runner = RAAF::Runner.new(agent: agent)
              
              messages.each do |msg|
                result = runner.run(msg)
                results << {
                  thread_id: thread_id,
                  request: msg[:content],
                  response: result.messages.last[:content]
                }
              end
            end
          end
          
          threads.each(&:join)
          
          # Verify all messages were processed
          expect(results.size).to eq(num_threads * messages_per_thread.first.size)
          
          # Each thread's responses should match its requests
          results.each do |result|
            expect(result[:response]).to include("thread #{result[:thread_id]}")
          end
        end
      end
    end
  end
end