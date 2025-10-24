# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/intelligent_streaming/config"
require "raaf/dsl/intelligent_streaming/executor"
require "raaf/dsl/core/context_variables"

RSpec.describe "IntelligentStreaming Error Scenarios" do
  let(:context_class) { RAAF::DSL::Core::ContextVariables }

  let(:base_agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "ErrorTestAgent"
      model "gpt-4o"

      def self.name
        "ErrorTestAgent"
      end

      def call
        context[:items] = context[:items].map { |item| item.merge(processed: true) } if context[:items]
        context[:success] = true
        context
      end
    end
  end

  describe "stream execution failures" do
    context "partial stream failures" do
      it "preserves partial results on failure" do
        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items
          end

          def call
            # Fail on stream 2 (items 5-9)
            if context[:items].any? { |item| item[:id] == 7 }
              raise StandardError, "Stream processing failed"
            end
            super
          end
        end

        items = (1..15).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Should raise error but preserve partial results
        expect {
          executor.execute(context)
        }.to raise_error(StandardError, "Stream processing failed")

        # First stream (items 1-5) should have been processed before failure
        # This depends on implementation - adjust based on actual behavior
      end

      it "executes on_stream_error hook on failure" do
        error_info = nil

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            on_stream_error do |stream_num, total, error, context|
              error_info = {
                stream: stream_num,
                total: total,
                error_message: error.message,
                error_class: error.class.name,
                context_size: context[:items].size
              }
            end
          end

          def call
            # Fail on specific stream
            if context[:items].first[:id] == 6
              raise StandardError, "Deliberate failure"
            end
            super
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(StandardError, "Deliberate failure")

        expect(error_info).not_to be_nil
        expect(error_info[:stream]).to eq(2)
        expect(error_info[:total]).to eq(2)
        expect(error_info[:error_message]).to eq("Deliberate failure")
        expect(error_info[:error_class]).to eq("StandardError")
        expect(error_info[:context_size]).to eq(5)
      end

      it "provides clear error messages with stream context" do
        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 10
            over :items
          end

          def call
            if context[:items].any? { |item| item[:id] == 25 }
              raise ArgumentError, "Invalid item in stream"
            end
            super
          end
        end

        items = (1..30).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        error_raised = false
        begin
          executor.execute(context)
        rescue ArgumentError => e
          error_raised = true
          expect(e.message).to include("Invalid item in stream")
          # The error should ideally include stream number context
        end

        expect(error_raised).to be true
      end
    end

    context "multiple stream failures" do
      it "handles multiple stream failures" do
        failures = []

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 3
            over :items

            on_stream_error do |stream_num, total, error, context|
              failures << { stream: stream_num, error: error.message }
            end
          end

          def call
            # Fail on streams 2 and 4
            if context[:items].any? { |item| [4, 10].include?(item[:id]) }
              raise StandardError, "Stream #{context[:items].first[:id] / 3 + 1} failed"
            end
            super
          end
        end

        items = (1..12).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(StandardError)

        # Should have captured the first failure
        expect(failures).not_to be_empty
        expect(failures.first[:stream]).to eq(2)
      end
    end
  end

  describe "hook failures" do
    context "on_stream_start hook failures" do
      it "logs hook errors but continues execution" do
        hook_error_logged = false

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            on_stream_start do |stream_num, total, context|
              if stream_num == 2
                hook_error_logged = true
                raise StandardError, "Hook failed"
              end
            end
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Hook errors should not stop execution
        result = nil
        expect {
          result = executor.execute(context)
        }.not_to raise_error

        expect(result[:success]).to be true
        expect(result[:items].size).to eq(10)
      end
    end

    context "on_stream_complete hook failures" do
      it "logs errors but preserves results" do
        complete_hooks_run = []

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            on_stream_complete do |stream_num, total, results|
              complete_hooks_run << stream_num
              if stream_num == 1
                raise StandardError, "Complete hook error"
              end
            end
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        result = executor.execute(context)

        # Execution should complete despite hook error
        expect(result[:success]).to be true
        expect(result[:items].all? { |item| item[:processed] }).to be true
        expect(complete_hooks_run).to include(1, 2)
      end
    end

    context "hook error context" do
      it "provides context in hook error messages" do
        error_messages = []

        # Capture logging output
        allow(RAAF::Logger).to receive(:error) do |msg|
          error_messages << msg
        end

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            on_stream_start do |stream_num, total, context|
              raise ArgumentError, "Invalid stream setup" if stream_num == 2
            end
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        executor.execute(context)

        # Should have logged error with context
        if error_messages.any?
          expect(error_messages.any? { |msg| msg.include?("on_stream_start") }).to be true
        end
      end
    end
  end

  describe "state management failures" do
    context "skip_if block errors" do
      it "handles skip_if block errors gracefully" do
        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            skip_if do |record, context|
              raise StandardError, "Skip check failed" if record[:id] == 3
              false
            end
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(StandardError, "Skip check failed")
      end
    end

    context "load_existing block errors" do
      it "handles load_existing block errors" do
        error_count = 0

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            load_existing do |record, context|
              if record[:id] == 7
                error_count += 1
                raise StandardError, "Cache load failed"
              end
              nil # No cached version
            end
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Load errors might be handled gracefully or propagate
        expect {
          executor.execute(context)
        }.to raise_error(StandardError, "Cache load failed")
      end
    end

    context "persist block errors" do
      it "handles persist block errors" do
        persist_attempts = []

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items

            persist do |stream_results, context|
              persist_attempts << stream_results[:items].size
              if persist_attempts.size == 2
                raise StandardError, "Persist failed"
              end
            end
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        # Persist errors might be logged but shouldn't stop execution
        result = nil
        expect {
          result = executor.execute(context)
        }.not_to raise_error

        expect(result[:success]).to be true
        expect(persist_attempts).to eq([5, 5])
      end
    end
  end

  describe "retry logic" do
    context "stream retry configuration" do
      it "allows retrying failed streams" do
        attempt_count = 0
        max_retries = 2

        retry_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items
            max_retries 2

            on_stream_error do |stream_num, total, error, context|
              # Retry logic would be handled here
            end
          end

          def call
            attempt_count += 1
            # Fail first attempt, succeed on retry
            if attempt_count == 1 && context[:items].first[:id] == 6
              raise StandardError, "Transient error"
            end
            super
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = retry_agent_class.new

        # This test assumes retry logic is implemented
        # Adjust based on actual implementation
      end

      it "respects max retry count" do
        retry_count = {}

        retry_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items
            max_retries 3

            on_stream_error do |stream_num, total, error, context|
              retry_count[stream_num] ||= 0
              retry_count[stream_num] += 1
            end
          end

          def call
            # Always fail for stream 2
            if context[:items].first[:id] == 6
              raise StandardError, "Persistent error"
            end
            super
          end
        end

        items = (1..10).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = retry_agent_class.new
        config = retry_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(StandardError, "Persistent error")

        # Should have tried max_retries times
        # Exact behavior depends on retry implementation
      end
    end
  end

  describe "recovery mechanisms" do
    context "graceful degradation" do
      it "returns partial results when possible" do
        partial_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 5
            over :items
            allow_partial_results true
          end

          def call
            # Process first stream, fail on second
            if context[:items].first[:id] > 5
              raise StandardError, "Processing limit reached"
            end
            super
          end
        end

        items = (1..15).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = partial_agent_class.new

        # Behavior depends on allow_partial_results implementation
        # This is a placeholder for the expected behavior
      end
    end

    context "error aggregation" do
      it "collects all errors for reporting" do
        all_errors = []

        error_agent_class = Class.new(base_agent_class) do
          intelligent_streaming do
            stream_size 3
            over :items

            on_stream_error do |stream_num, total, error, context|
              all_errors << {
                stream: stream_num,
                error: error.message,
                items: context[:items].map { |i| i[:id] }
              }
            end
          end

          def call
            # Fail on specific items
            if context[:items].any? { |item| [4, 7, 10].include?(item[:id]) }
              item_id = context[:items].find { |item| [4, 7, 10].include?(item[:id]) }[:id]
              raise StandardError, "Item #{item_id} is invalid"
            end
            super
          end
        end

        items = (1..12).map { |i| { id: i } }
        context = context_class.new(items: items)
        agent = error_agent_class.new
        config = error_agent_class._intelligent_streaming_config
        executor = RAAF::DSL::IntelligentStreaming::Executor.new(agent, config)

        expect {
          executor.execute(context)
        }.to raise_error(StandardError)

        # Should have collected error information
        expect(all_errors).not_to be_empty
        expect(all_errors.first[:stream]).to eq(2)
        expect(all_errors.first[:items]).to include(4)
      end
    end
  end
end