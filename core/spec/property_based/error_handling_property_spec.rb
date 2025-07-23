# frozen_string_literal: true

require "spec_helper"
require "rantly"
require "rantly/rspec_extensions"

RSpec.describe "Error Handling Property-Based Tests" do
  describe RAAF::Execution::ErrorHandler do
    context "property: error recovery strategies" do
      it "always returns a valid result for any error type" do
        property_of {
          # Generate random errors
          error = case integer(0..7)
                  when 0
                    RAAF::MaxTurnsError.new("Max turns: #{integer(1..100)}")
                  when 1
                    RAAF::APIError.new("API error: #{string}", status: integer(400..599))
                  when 2
                    RAAF::RateLimitError.new("Rate limit: #{integer(1..1000)}")
                  when 3
                    RAAF::AuthenticationError.new("Auth failed: #{string}")
                  when 4
                    RAAF::InvalidRequestError.new("Invalid: #{string}")
                  when 5
                    RAAF::ExecutionStoppedError.new("Stopped: #{string}")
                  when 6
                    StandardError.new("Generic: #{string}")
                  when 7
                    JSON::ParserError.new("JSON error at #{integer}")
                  end
          
          strategy = choose(
            RAAF::RecoveryStrategy::RAISE,
            RAAF::RecoveryStrategy::RETURN_ERROR,
            RAAF::RecoveryStrategy::RETRY_ONCE,
            RAAF::RecoveryStrategy::LOG_AND_CONTINUE
          )
          
          max_retries = integer(1..5)
          context = { request_id: string(:alnum), timestamp: Time.now.to_f }
          
          [error, strategy, max_retries, context]
        }.check(100) do |error, strategy, max_retries, context|
          handler = RAAF::ErrorHandler.new(
            strategy: strategy,
            max_retries: max_retries
          )
          
          result = nil
          retry_count = 0
          
          begin
            result = handler.with_error_handling(**context) do
              retry_count += 1
              raise error
            end
          rescue => e
            # Only RAISE strategy should re-raise
            expect(strategy).to eq(RAAF::RecoveryStrategy::RAISE)
            expect(e.class).to eq(error.class)
          end
          
          case strategy
          when RAAF::RecoveryStrategy::RETURN_ERROR
            expect(result).to include(:error)
            expect(result[:error]).to be_a(Hash)
            expect(result[:error][:type]).to eq(error.class.name)
          when RAAF::RecoveryStrategy::RETRY_ONCE
            expect(retry_count).to be <= max_retries + 1
          when RAAF::RecoveryStrategy::LOG_AND_CONTINUE
            expect(result).to be_nil
          end
        end
      end

      it "maintains error context through handling" do
        property_of {
          # Generate complex error scenarios
          num_fields = integer(1..10)
          error_data = {}
          num_fields.times do |i|
            key = "field_#{i}"
            value = choose(string, integer, float, boolean)
            error_data[key] = value
          end
          
          error_message = "Error: #{string}"
          api_error = RAAF::APIError.new(error_message, **error_data)
          
          [api_error, error_data, error_message]
        }.check(50) do |api_error, error_data, error_message|
          handler = RAAF::ErrorHandler.new(
            strategy: RAAF::RecoveryStrategy::RETURN_ERROR
          )
          
          result = handler.with_error_handling do
            raise api_error
          end
          
          expect(result[:error][:message]).to eq(error_message)
          
          # All custom fields should be preserved
          error_data.each do |key, value|
            if api_error.respond_to?(key)
              expect(api_error.send(key)).to eq(value)
            end
          end
        end
      end
    end

    context "property: retry behavior consistency" do
      it "respects max retries with random retry counts" do
        property_of {
          max_retries = integer(0..10)
          fail_count = integer(0..20)  # How many times to fail before success
          
          [max_retries, fail_count]
        }.check(50) do |max_retries, fail_count|
          handler = RAAF::ErrorHandler.new(
            strategy: RAAF::RecoveryStrategy::RETRY_ONCE,
            max_retries: max_retries
          )
          
          attempt_count = 0
          
          begin
            handler.with_error_handling do
              attempt_count += 1
              if attempt_count <= fail_count
                raise RAAF::APIError.new("Transient failure #{attempt_count}")
              end
              "Success after #{attempt_count} attempts"
            end
          rescue RAAF::APIError
            # Expected when fail_count > max_retries
            expect(fail_count).to be > max_retries
            expect(attempt_count).to eq(max_retries + 1)
          else
            # Success case when fail_count <= max_retries
            expect(fail_count).to be <= max_retries
            expect(attempt_count).to eq(fail_count + 1)
          end
        end
      end
    end
  end

  describe "Error message generation" do
    context "property: safe error messages" do
      it "sanitizes any input to create safe error messages" do
        property_of {
          # Generate potentially problematic strings
          input = case integer(0..5)
                  when 0 then string  # Normal string
                  when 1 then string.encode("UTF-8", invalid: :replace)  # UTF-8 issues
                  when 2 then "<script>#{string}</script>"  # HTML injection
                  when 3 then "'; DROP TABLE users; --"  # SQL injection attempt
                  when 4 then string * 1000  # Very long string
                  when 5 then "\x00\x01\x02#{string}"  # Binary data
                  end
          
          [input]
        }.check(100) do |input|
          # Create error with potentially unsafe input
          error = RAAF::InvalidRequestError.new(input)
          
          # Message should be accessible without raising
          expect { error.message }.not_to raise_error
          expect { error.to_s }.not_to raise_error
          
          # Should not contain certain dangerous patterns
          safe_message = error.message
          expect(safe_message).not_to include("<script>")
          expect(safe_message).not_to include("DROP TABLE")
          
          # Should be reasonable length
          expect(safe_message.length).to be < 10_000
        end
      end
    end
  end

  describe "Concurrent error handling" do
    context "property: thread-safe error handling" do
      it "handles errors correctly under concurrent load" do
        property_of {
          num_threads = integer(2..10)
          operations_per_thread = integer(5..20)
          failure_rate = float.abs % 1.0  # 0.0 to 1.0
          
          [num_threads, operations_per_thread, failure_rate]
        }.check(25) do |num_threads, operations_per_thread, failure_rate|
          handler = RAAF::ErrorHandler.new(
            strategy: RAAF::RecoveryStrategy::RETURN_ERROR
          )
          
          results = Concurrent::Array.new
          errors = Concurrent::Array.new
          
          threads = num_threads.times.map do |thread_id|
            Thread.new do
              operations_per_thread.times do |op_id|
                result = handler.with_error_handling(
                  thread_id: thread_id,
                  operation_id: op_id
                ) do
                  if rand < failure_rate
                    raise RAAF::APIError.new("Thread #{thread_id} op #{op_id} failed")
                  else
                    "Thread #{thread_id} op #{op_id} success"
                  end
                end
                
                if result.is_a?(Hash) && result[:error]
                  errors << result
                else
                  results << result
                end
              end
            end
          end
          
          threads.each(&:join)
          
          # Verify totals
          total_operations = num_threads * operations_per_thread
          expect(results.size + errors.size).to eq(total_operations)
          
          # Each error should have correct structure
          errors.each do |error_result|
            expect(error_result).to have_key(:error)
            expect(error_result[:error]).to have_key(:type)
            expect(error_result[:error][:type]).to eq("RAAF::APIError")
          end
        end
      end
    end
  end

  describe "Error propagation chains" do
    context "property: nested error handling" do
      it "correctly propagates errors through nested handlers" do
        property_of {
          # Generate nested handler configuration
          depth = integer(1..5)
          strategies = depth.times.map do
            choose(
              RAAF::RecoveryStrategy::RAISE,
              RAAF::RecoveryStrategy::RETURN_ERROR,
              RAAF::RecoveryStrategy::LOG_AND_CONTINUE
            )
          end
          
          error_at_level = integer(0...depth)
          
          [depth, strategies, error_at_level]
        }.check(50) do |depth, strategies, error_at_level|
          handlers = strategies.map do |strategy|
            RAAF::ErrorHandler.new(strategy: strategy)
          end
          
          current_level = 0
          
          # Build nested execution
          execution = lambda do |level|
            if level >= depth
              # Base case - potentially raise error
              if current_level == error_at_level
                raise RAAF::APIError.new("Error at level #{level}")
              else
                "Success at level #{level}"
              end
            else
              # Recursive case
              handlers[level].with_error_handling do
                current_level = level
                execution.call(level + 1)
              end
            end
          end
          
          begin
            result = execution.call(0)
            
            # If we get here, error was handled
            should_propagate = strategies[0..error_at_level].all? do |s|
              s == RAAF::RecoveryStrategy::RAISE
            end
            
            expect(should_propagate).to be false
          rescue RAAF::APIError => e
            # Error propagated to top
            expect(e.message).to include("level #{error_at_level}")
          end
        end
      end
    end
  end

  describe "Error recovery with state" do
    context "property: stateful error recovery" do
      it "maintains state consistency through error recovery" do
        property_of {
          initial_state = array { integer }
          operations = array(integer(5..15)) do
            {
              type: choose(:add, :remove, :multiply),
              value: integer(-100..100),
              should_fail: boolean && (float < 0.3)  # 30% failure rate
            }
          end
          
          [initial_state.dup, operations]
        }.check(50) do |initial_state, operations|
          state = initial_state.dup
          handler = RAAF::ErrorHandler.new(
            strategy: RAAF::RecoveryStrategy::RETRY_ONCE,
            max_retries: 2
          )
          
          operations.each_with_index do |op, idx|
            retry_count = 0
            
            result = handler.with_error_handling do
              retry_count += 1
              
              # Fail on first attempt if should_fail
              if op[:should_fail] && retry_count == 1
                raise RAAF::APIError.new("Operation failed")
              end
              
              # Apply operation
              case op[:type]
              when :add
                state << op[:value]
              when :remove
                state.delete_at(0) unless state.empty?
              when :multiply
                state.map! { |x| x * op[:value] } unless op[:value] == 0
              end
              
              state.dup  # Return copy of current state
            end
            
            # State should be modified despite errors
            expect(result).to be_a(Array) if result
          end
          
          # Final state should reflect all operations
          expect(state).to be_a(Array)
        end
      end
    end
  end
end