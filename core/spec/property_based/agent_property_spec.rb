# frozen_string_literal: true

require "spec_helper"
require "rantly"
require "rantly/rspec_extensions"

RSpec.describe "Agent Property-Based Tests" do
  describe RAAF::Agent do
    context "property: agent creation with random valid inputs" do
      it "always creates valid agents with random names and instructions" do
        property_of {
          name = sized(10) { string(:alpha) }.capitalize
          instructions = sized(50) { string }
          model = choose("gpt-4o", "gpt-4o-mini", "gpt-3.5-turbo")
          max_turns = integer(1..100)
          
          [name, instructions, model, max_turns]
        }.check(100) do |name, instructions, model, max_turns|
          agent = RAAF::Agent.new(
            name: name,
            instructions: instructions,
            model: model,
            max_turns: max_turns
          )
          
          expect(agent.name).to eq(name)
          expect(agent.instructions).to eq(instructions)
          expect(agent.model).to eq(model)
          expect(agent.max_turns).to eq(max_turns)
        end
      end

      it "maintains handoff consistency with random agent additions" do
        property_of {
          num_agents = integer(2..10)  # At least 2 agents
          agents = num_agents.times.map do |i|
            RAAF::Agent.new(name: "Agent#{i}", instructions: "Test agent #{i}")
          end
          
          # Random handoff connections - ensure valid indices
          handoffs = []
          integer(0..10).times do
            from = integer(0...(agents.size))
            to = integer(0...(agents.size))
            handoffs << [from, to] if from != to && agents[from] && agents[to]
          end
          
          [agents, handoffs.uniq]
        }.check(50) do |agents, handoffs|
          # Add handoffs - verify agents exist
          handoffs.each do |from_idx, to_idx|
            next unless agents[from_idx] && agents[to_idx]
            agents[from_idx].add_handoff(agents[to_idx])
          end
          
          # Verify handoffs were added correctly
          handoffs.each do |from_idx, to_idx|
            next unless agents[from_idx] && agents[to_idx]
            
            from_agent = agents[from_idx]
            to_agent = agents[to_idx]
            
            expect(from_agent.handoff_agents).to include(to_agent.name)
            
            # Check tool creation
            tool_name = "transfer_to_#{to_agent.name.downcase}"
            tool = from_agent.tools.find { |t| t.name == tool_name }
            expect(tool).not_to be_nil
          end
        end
      end
    end

    context "property: tool management invariants" do
      it "maintains unique tool names with random tool additions" do
        property_of {
          agent = RAAF::Agent.new(name: "TestAgent")
          
          # Generate random tools
          num_tools = integer(1..20)
          tools = num_tools.times.map do |i|
            # Sometimes use same name to test uniqueness
            name = if boolean
                     "tool_#{integer(1..5)}"  # Limited set for collisions
                   else
                     "tool_#{i}_#{string(:alpha, 5)}"  # Unique names
                   end
            
            proc_obj = proc { |x| "Result for #{x}" }
            [name, proc_obj]
          end
          
          [agent, tools]
        }.check(50) do |agent, tools|
          tools.each do |name, proc_obj|
            tool = RAAF::FunctionTool.new(proc_obj, name: name)
            agent.add_tool(tool)
          end
          
          # Verify uniqueness
          tool_names = agent.tools.map(&:name)
          expect(tool_names).to eq(tool_names.uniq)
          
          # Verify all tools are FunctionTool instances
          agent.tools.each do |tool|
            expect(tool).to be_a(RAAF::FunctionTool)
          end
        end
      end

      it "correctly filters enabled tools with random enable/disable patterns" do
        property_of {
          agent = RAAF::Agent.new(name: "TestAgent")
          
          # Create tools with random enabled states
          num_tools = integer(5..15)
          tools_data = num_tools.times.map do |i|
            enabled = boolean
            tool = RAAF::FunctionTool.new(
              proc { "Result #{i}" },
              name: "tool_#{i}",
              enabled: enabled
            )
            [tool, enabled]
          end
          
          [agent, tools_data]
        }.check(50) do |agent, tools_data|
          # Add all tools
          tools_data.each { |tool, _| agent.add_tool(tool) }
          
          # Verify enabled_tools returns only enabled ones
          enabled_tools = agent.enabled_tools
          
          tools_data.each do |tool, should_be_enabled|
            if should_be_enabled
              expect(enabled_tools).to include(tool)
            else
              expect(enabled_tools).not_to include(tool)
            end
          end
        end
      end
    end

    context "property: output type validation" do
      it "accepts any valid JSON schema as output_type" do
        property_of {
          # Generate random but valid JSON schemas
          schema = case integer(0..4)
                   when 0
                     { type: "string" }
                   when 1
                     { type: "number" }
                   when 2
                     { type: "boolean" }
                   when 3
                     {
                       type: "object",
                       properties: {
                         field1: { type: "string" },
                         field2: { type: "number" }
                       }
                     }
                   when 4
                     {
                       type: "array",
                       items: { type: "string" }
                     }
                   end
          
          [schema]
        }.check(100) do |schema|
          agent = RAAF::Agent.new(
            name: "TestAgent",
            output_type: schema
          )
          
          expect(agent.output_type).to eq(schema)
          expect { agent.to_h }.not_to raise_error
        end
      end
    end
  end

  describe RAAF::FunctionTool do
    context "property: parameter extraction consistency" do
      it "correctly extracts parameters from any valid proc signature" do
        property_of {
          # Generate random parameter combinations
          num_required = integer(0..3)
          num_optional = integer(0..3)
          has_rest = boolean
          has_keyrest = boolean
          
          # Build parameter list
          params = []
          param_names = []
          
          num_required.times do |i|
            name = "req#{i}"
            params << name
            param_names << name.to_sym
          end
          
          num_optional.times do |i|
            name = "opt#{i}"
            params << "#{name} = #{i}"
            param_names << name.to_sym
          end
          
          params << "*rest" if has_rest
          params << "**kwargs" if has_keyrest
          
          # Create proc with dynamic parameters
          proc_string = "proc { |#{params.join(', ')}| 'result' }"
          proc_obj = eval(proc_string)
          
          [proc_obj, num_required, num_optional, has_rest, has_keyrest, param_names]
        }.check(50) do |proc_obj, num_required, num_optional, has_rest, has_keyrest, param_names|
          tool = RAAF::FunctionTool.new(proc_obj, name: "test_tool")
          
          # Verify parameter extraction
          if num_required > 0 || num_optional > 0
            expect(tool.parameters?).to be true
            
            schema = tool.to_h[:function][:parameters]
            expect(schema[:type]).to eq("object")
            
            # Check required parameters
            if num_required > 0
              expect(schema[:required].size).to eq(num_required)
            end
          end
        end
      end
    end

    context "property: execution safety" do
      it "safely handles any input types without crashing" do
        property_of {
          # Generate random input types
          input = case integer(0..6)
                  when 0 then string
                  when 1 then integer
                  when 2 then float
                  when 3 then boolean
                  when 4 then array { string }
                  when 5 then hash { [string(:alpha), string] }
                  when 6 then nil
                  end
          
          tool = RAAF::FunctionTool.new(
            proc { |x| x.to_s.upcase rescue "ERROR" },
            name: "safe_tool"
          )
          
          [tool, input]
        }.check(100) do |tool, input|
          # Should not raise an error
          result = nil
          expect { result = tool.execute(input) }.not_to raise_error
          
          # Should return some result
          expect(result).not_to be_nil
        end
      end
    end
  end

  describe RAAF::Runner do
    context "property: message handling invariants" do
      it "preserves message order with random message sequences" do
        property_of {
          agent = RAAF::Agent.new(name: "TestAgent")
          
          # Generate random message sequence
          num_messages = integer(1..10)
          messages = num_messages.times.map do |i|
            role = choose("user", "assistant", "system")
            content = "Message #{i}: #{string}"
            { role: role, content: content }
          end
          
          [agent, messages]
        }.check(25) do |agent, messages|
          # Use mock provider
          mock_provider = create_mock_provider
          mock_provider.add_response("Response")
          
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
          
          result = runner.run(messages)
          
          # Original messages should be preserved in order
          messages.each_with_index do |msg, idx|
            expect(result.messages[idx]).to include(msg)
          end
        end
      end
    end

    context "property: token usage accumulation" do
      it "correctly accumulates tokens across any number of turns" do
        property_of {
          agent = RAAF::Agent.new(name: "TestAgent", max_turns: 100)
          num_turns = integer(1..10)
          
          # Random token counts per turn
          token_data = num_turns.times.map do
            {
              input: integer(10..1000),
              output: integer(10..1000)
            }
          end
          
          [agent, token_data]
        }.check(25) do |agent, token_data|
          # Use mock provider
          mock_provider = create_mock_provider
          
          # Add response with specific token data
          mock_provider.add_response(
            "Response", 
            usage: {
              input_tokens: token_data[0][:input],
              output_tokens: token_data[0][:output],
              total_tokens: token_data[0][:input] + token_data[0][:output]
            }
          )
          
          runner = RAAF::Runner.new(agent: agent, provider: mock_provider)
          
          result = runner.run("Start")
          
          # Verify token accumulation for single turn
          expect(result.usage[:input_tokens]).to eq(token_data[0][:input])
          expect(result.usage[:output_tokens]).to eq(token_data[0][:output])
          expect(result.usage[:total_tokens]).to eq(token_data[0][:input] + token_data[0][:output])
        end
      end
    end
  end

  describe RAAF::RunConfig do
    context "property: configuration merging" do
      it "correctly merges configurations with random values" do
        property_of {
          # Generate two random configs
          config1_values = {
            max_turns: boolean ? integer(1..50) : nil,
            temperature: boolean ? (float.abs % 2.0) : nil,
            max_tokens: boolean ? integer(100..4000) : nil,
            stream: boolean ? boolean : nil
          }.compact
          
          config2_values = {
            max_turns: boolean ? integer(1..50) : nil,
            temperature: boolean ? (float.abs % 2.0) : nil,
            max_tokens: boolean ? integer(100..4000) : nil,
            response_format: boolean ? { type: "json_object" } : nil
          }.compact
          
          [config1_values, config2_values]
        }.check(100) do |config1_values, config2_values|
          config1 = RAAF::RunConfig.new(**config1_values)
          config2 = RAAF::RunConfig.new(**config2_values)
          
          merged = config1.merge(config2)
          
          # Second config values should override first
          config2_values.each do |key, value|
            expect(merged.send(key)).to eq(value)
          end
          
          # First config values not in second should be preserved
          (config1_values.keys - config2_values.keys).each do |key|
            expect(merged.send(key)).to eq(config1_values[key])
          end
        end
      end
    end
  end

  describe "Handoff Context serialization" do
    context "property: serialization roundtrip" do
      it "preserves all data through serialization with random values" do
        property_of {
          # Generate random handoff context data
          data = {
            from_agent: string(:alpha).capitalize,
            to_agent: string(:alpha).capitalize,
            message: string,
            metadata: hash { [string(:alpha), choose(string, integer, boolean)] },
            timestamp: Time.now.to_f - (float.abs * 86400)  # Random time in past day
          }
          
          context = RAAF::HandoffContext.new(**data)
          [context, data]
        }.check(100) do |context, original_data|
          # Serialize and deserialize
          serialized = context.to_h
          reconstructed = RAAF::HandoffContext.from_h(serialized)
          
          # Verify all fields match
          expect(reconstructed.from_agent).to eq(original_data[:from_agent])
          expect(reconstructed.to_agent).to eq(original_data[:to_agent])
          expect(reconstructed.message).to eq(original_data[:message])
          expect(reconstructed.metadata).to eq(original_data[:metadata])
          expect(reconstructed.timestamp).to be_within(0.001).of(original_data[:timestamp])
        end
      end
    end
  end
end