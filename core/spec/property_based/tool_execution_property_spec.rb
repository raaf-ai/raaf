# frozen_string_literal: true

require "spec_helper"
require "rantly"
require "rantly/rspec_extensions"

RSpec.describe "Tool Execution Property-Based Tests" do
  describe RAAF::Execution::ToolExecutor do
    let(:runner) { double("Runner") }
    let(:executor) { RAAF::Execution::ToolExecutor.new(runner) }

    context "property: tool execution with any input types" do
      it "safely executes tools with random argument types" do
        property_of {
          # Generate random tool signature
          num_params = integer(0..5)
          param_types = num_params.times.map do
            choose(:required, :optional, :keyword, :keyrest)
          end
          
          # Generate matching arguments
          args = case integer(0..4)
                 when 0 then string
                 when 1 then integer
                 when 2 then hash { [string(:alpha), choose(string, integer, boolean)] }
                 when 3 then array { choose(string, integer) }
                 when 4 then { nested: { data: array { string } } }
                 end
          
          # Create tool based on signature
          tool = case param_types.first
                 when :required
                   RAAF::FunctionTool.new(
                     proc { |x| "Processed: #{x}" },
                     name: "test_tool"
                   )
                 when :keyword
                   RAAF::FunctionTool.new(
                     proc { |value:| "Keyword: #{value}" },
                     name: "test_tool"
                   )
                 else
                   RAAF::FunctionTool.new(
                     proc { |*args, **kwargs| "Args: #{args}, Kwargs: #{kwargs}" },
                     name: "test_tool"
                   )
                 end
          
          [tool, args]
        }.check(100) do |tool, args|
          # Execute tool with random arguments
          result = executor.execute_tool(tool, args, "call_123")
          
          # Should always return a result message
          expect(result).to be_a(Hash)
          expect(result[:role]).to eq("tool")
          expect(result[:tool_call_id]).to eq("call_123")
          expect(result[:content]).to be_a(String)
          
          # Should not raise errors
          expect(result[:content]).not_to include("Error executing tool")
        end
      end
    end

    context "property: argument parsing robustness" do
      it "correctly parses any valid JSON arguments" do
        property_of {
          # Generate random but valid JSON structures
          json_value = case integer(0..6)
                       when 0 then string
                       when 1 then integer
                       when 2 then float
                       when 3 then boolean
                       when 4 then array { choose(string, integer) }
                       when 5 then hash { [string(:alpha), choose(string, integer, boolean)] }
                       when 6 then nil
                       end
          
          json_string = JSON.generate(json_value)
          
          [json_string, json_value]
        }.check(100) do |json_string, expected_value|
          tool = RAAF::FunctionTool.new(
            proc { |args| "Received: #{args.inspect}" },
            name: "json_tool"
          )
          
          result = executor.execute_tool(tool, json_string, "call_json")
          
          # Should successfully parse and execute
          expect(result[:role]).to eq("tool")
          expect(result[:content]).to include("Received:")
          
          # Verify parsing worked
          if expected_value.nil?
            expect(result[:content]).to include("nil")
          else
            expect(result[:content]).to include(expected_value.to_s)
          end
        end
      end

      it "handles malformed JSON gracefully" do
        property_of {
          # Generate invalid JSON
          malformed = case integer(0..5)
                      when 0 then "{"  # Incomplete object
                      when 1 then "[1, 2,"  # Incomplete array
                      when 2 then "{key: value}"  # Unquoted keys
                      when 3 then "{'key': 'value'}"  # Single quotes
                      when 4 then "undefined"  # JavaScript keyword
                      when 5 then string  # Random string
                      end
          
          [malformed]
        }.check(50) do |malformed|
          tool = RAAF::FunctionTool.new(
            proc { |x| "Should not reach here" },
            name: "malformed_tool"
          )
          
          result = executor.execute_tool(tool, malformed, "call_bad")
          
          # Should handle error gracefully
          expect(result[:role]).to eq("tool")
          expect(result[:content]).to match(/Error executing tool|JSON|parse/i)
        end
      end
    end

    context "property: concurrent tool execution" do
      it "executes multiple tools concurrently without interference" do
        property_of {
          num_tools = integer(2..10)
          
          tools = num_tools.times.map do |i|
            delay = float.abs * 0.1  # 0 to 0.1 seconds
            
            tool = RAAF::FunctionTool.new(
              proc do |tool_id:|
                sleep(delay)
                "Tool #{tool_id} completed after #{delay}s"
              end,
              name: "concurrent_tool_#{i}"
            )
            
            [tool, { tool_id: i }, delay]
          end
          
          [tools]
        }.check(25) do |tools|
          results = Concurrent::Array.new
          
          threads = tools.map do |tool, args, expected_delay|
            Thread.new do
              args_json = JSON.generate(args)
              result = executor.execute_tool(tool, args_json, "call_#{tool.name}")
              results << result
            end
          end
          
          threads.each(&:join)
          
          # All tools should complete
          expect(results.size).to eq(tools.size)
          
          # Each result should be independent
          results.each_with_index do |result, i|
            expect(result[:content]).to include("Tool #{i}")
            expect(result[:role]).to eq("tool")
          end
        end
      end
    end

    context "property: tool result serialization" do
      it "serializes any tool return value to valid JSON" do
        property_of {
          # Generate various return types
          return_value = case integer(0..10)
                         when 0 then string
                         when 1 then integer
                         when 2 then float
                         when 3 then boolean
                         when 4 then nil
                         when 5 then array { choose(string, integer) }
                         when 6 then hash { [string(:alpha), choose(string, integer)] }
                         when 7 then Time.now  # Complex object
                         when 8 then /regex/  # Regex
                         when 9 then Object.new  # Generic object
                         when 10 then circular = {}; circular[:self] = circular; circular
                         end
          
          tool = RAAF::FunctionTool.new(
            proc { return_value },
            name: "serialization_tool"
          )
          
          [tool, return_value]
        }.check(100) do |tool, return_value|
          result = executor.execute_tool(tool, "{}", "call_serialize")
          
          # Should always produce a valid result
          expect(result[:role]).to eq("tool")
          expect(result[:content]).to be_a(String)
          
          # Content should be valid JSON or error message
          begin
            parsed = JSON.parse(result[:content])
            # Successfully parsed means it was serialized properly
            expect(parsed).not_to be_nil
          rescue JSON::ParserError
            # If not JSON, should be a readable string
            expect(result[:content]).not_to be_empty
          end
        end
      end
    end

    context "property: error handling completeness" do
      it "handles any exception type gracefully" do
        property_of {
          # Generate different exception types
          exception = case integer(0..7)
                      when 0 then StandardError.new("Generic error")
                      when 1 then ArgumentError.new("Wrong arguments")
                      when 2 then NoMethodError.new("Method missing")
                      when 3 then RuntimeError.new("Runtime problem")
                      when 4 then JSON::ParserError.new("JSON issue")
                      when 5 then Encoding::UndefinedConversionError.new("Encoding")
                      when 6 then SystemStackError.new("Stack too deep")
                      when 7 then Exception.new("Base exception")
                      end
          
          tool = RAAF::FunctionTool.new(
            proc { raise exception },
            name: "error_tool"
          )
          
          [tool, exception]
        }.check(100) do |tool, exception|
          result = executor.execute_tool(tool, "{}", "call_error")
          
          # Should never raise to caller
          expect(result).to be_a(Hash)
          expect(result[:role]).to eq("tool")
          expect(result[:content]).to be_a(String)
          
          # Should contain error information
          expect(result[:content]).to match(/Error|error|failed/i)
        end
      end
    end

    context "property: parameter validation" do
      it "validates required parameters with any argument combination" do
        property_of {
          # Define required and optional parameters
          required_params = array(integer(1..3)) { string(:alpha, 5) }
          optional_params = array(integer(0..3)) { string(:alpha, 5) }
          
          # Generate arguments that may or may not include all required
          provided_params = {}
          
          # Sometimes provide all required
          if boolean
            required_params.each { |p| provided_params[p.to_sym] = string }
          else
            # Provide subset
            required_params.sample(integer(0...required_params.size)).each do |p|
              provided_params[p.to_sym] = string
            end
          end
          
          # Add some optional
          optional_params.sample(integer(0..optional_params.size)).each do |p|
            provided_params[p.to_sym] = string
          end
          
          # Create tool with specific signature
          params = required_params.map { |p| "#{p}:" }.join(", ")
          params += ", " unless params.empty? || optional_params.empty?
          params += optional_params.map { |p| "#{p}: nil" }.join(", ")
          
          tool_proc = eval("proc { |#{params}| 'Success' }")
          tool = RAAF::FunctionTool.new(tool_proc, name: "param_tool")
          
          [tool, provided_params, required_params]
        }.check(50) do |tool, provided_params, required_params|
          result = executor.execute_tool(
            tool,
            JSON.generate(provided_params),
            "call_params"
          )
          
          # Check if all required params were provided
          all_required_provided = required_params.all? do |req|
            provided_params.key?(req.to_sym)
          end
          
          if all_required_provided
            # Should succeed
            expect(result[:content]).not_to include("Error")
          else
            # Should report missing parameters
            expect(result[:content]).to match(/Error|missing|required/i)
          end
        end
      end
    end

    context "property: Unicode and encoding safety" do
      it "handles any Unicode input correctly" do
        property_of {
          # Generate various Unicode strings
          unicode_input = case integer(0..5)
                          when 0 then "Hello 世界 🌍"  # Mixed scripts
                          when 1 then "مرحبا بالعالم"  # Arabic
                          when 2 then "Здравствуй мир"  # Cyrillic
                          when 3 then "🚀🎨🎭🎪🎯"  # Emojis
                          when 4 then "\u{1F600}\u{1F601}\u{1F602}"  # Unicode escapes
                          when 5
                            # Random Unicode
                            array(integer(5..20)) do
                              code_point = integer(0x80..0x10FFFF)
                              code_point.chr(Encoding::UTF_8) rescue "?"
                            end.join
                          end
          
          tool = RAAF::FunctionTool.new(
            proc { |text:| "Processed: #{text}" },
            name: "unicode_tool"
          )
          
          [tool, unicode_input]
        }.check(100) do |tool, unicode_input|
          args = { text: unicode_input }
          result = executor.execute_tool(
            tool,
            JSON.generate(args),
            "call_unicode"
          )
          
          # Should handle Unicode without errors
          expect(result[:role]).to eq("tool")
          expect(result[:content]).to be_a(String)
          expect(result[:content].encoding).to eq(Encoding::UTF_8)
          
          # Should preserve or safely handle Unicode
          if result[:content].include?("Processed:")
            expect(result[:content]).to include(unicode_input)
          end
        end
      end
    end

    context "property: performance boundaries" do
      it "handles tools with varying execution times" do
        property_of {
          # Generate execution time in seconds
          execution_time = case integer(0..3)
                           when 0 then 0  # Instant
                           when 1 then float.abs * 0.01  # Fast (0-10ms)
                           when 2 then float.abs * 0.1   # Medium (0-100ms)
                           when 3 then float.abs * 0.5   # Slow (0-500ms)
                           end
          
          # Generate result size
          result_size = case integer(0..3)
                        when 0 then 10        # Small
                        when 1 then 1000      # Medium
                        when 2 then 10_000    # Large
                        when 3 then 100_000   # Very large
                        end
          
          tool = RAAF::FunctionTool.new(
            proc do
              sleep(execution_time)
              "x" * result_size
            end,
            name: "performance_tool"
          )
          
          [tool, execution_time, result_size]
        }.check(25) do |tool, execution_time, result_size|
          start_time = Time.now
          result = executor.execute_tool(tool, "{}", "call_perf")
          end_time = Time.now
          
          # Should complete within reasonable time
          expect(end_time - start_time).to be < (execution_time + 1.0)
          
          # Should handle large results
          expect(result[:content].size).to be >= [result_size, 1_000_000].min
        end
      end
    end
  end
end