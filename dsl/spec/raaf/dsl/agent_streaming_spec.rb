# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/agent"
require "raaf/dsl/intelligent_streaming"
require "concurrent"

RSpec.describe "RAAF::DSL::Agent intelligent streaming" do
  # Create a test agent class for each test to avoid state pollution
  let(:agent_class) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "TestStreamingAgent"
      model "gpt-4o"
    end
  end

  describe ".intelligent_streaming" do
    context "basic configuration" do
      it "configures intelligent streaming with stream_size and field" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies
        end

        expect(agent_class.streaming_trigger?).to be(true)
        expect(agent_class.streaming_config?).to be(true)

        config = agent_class.streaming_config
        expect(config).to be_a(RAAF::DSL::IntelligentStreaming::Config)
        expect(config.stream_size).to eq(100)
        expect(config.array_field).to eq(:companies)
        expect(config.incremental).to be(false)
      end

      it "configures with incremental delivery enabled" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 50, over: :items, incremental: true
        end

        config = agent_class.streaming_config
        expect(config.incremental).to be(true)
      end

      it "auto-detects array field when not specified" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100
        end

        config = agent_class.streaming_config
        expect(config.array_field).to be_nil
      end
    end

    context "with state management blocks" do
      it "configures skip_if block" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies do
            skip_if { |record| record[:processed] }
          end
        end

        config = agent_class.streaming_config
        expect(config.blocks[:skip_if]).not_to be_nil
        expect(config.blocks[:skip_if].call({ processed: true })).to be(true)
        expect(config.blocks[:skip_if].call({ processed: false })).to be(false)
      end

      it "configures load_existing block" do
        cache = { 1 => "cached_result" }
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies do
            load_existing { |record| cache[record[:id]] }
          end
        end

        config = agent_class.streaming_config
        expect(config.blocks[:load_existing]).not_to be_nil
        expect(config.blocks[:load_existing].call({ id: 1 }, cache)).to eq("cached_result")
      end

      it "configures persist_each_stream block" do
        saved_results = []
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies do
            persist_each_stream { |results| saved_results.concat(results) }
          end
        end

        config = agent_class.streaming_config
        config.blocks[:persist_each_stream].call([1, 2, 3], saved_results)
        expect(saved_results).to eq([1, 2, 3])
      end
    end

    context "with progress hooks" do
      it "configures on_stream_start hook" do
        log = []
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies do
            on_stream_start { |num, total, data| log << "Start #{num}/#{total}" }
          end
        end

        config = agent_class.streaming_config
        config.blocks[:on_stream_start].call(1, 10, [], log)
        expect(log).to eq(["Start 1/10"])
      end

      it "configures on_stream_complete hook for non-incremental mode" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies, incremental: false do
            on_stream_complete { |all_results| puts "Done: #{all_results.size}" }
          end
        end

        config = agent_class.streaming_config
        expect(config.blocks[:on_stream_complete]).not_to be_nil
        expect(config.blocks[:on_stream_complete].arity).to eq(1)
      end

      it "configures on_stream_complete hook for incremental mode" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies, incremental: true do
            on_stream_complete { |num, total, results| puts "Stream #{num}/#{total}" }
          end
        end

        config = agent_class.streaming_config
        expect(config.blocks[:on_stream_complete]).not_to be_nil
        expect(config.blocks[:on_stream_complete].arity).to eq(3)
      end

      it "configures on_stream_error hook" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies do
            on_stream_error { |num, total, error, context| puts "Error in stream #{num}" }
          end
        end

        config = agent_class.streaming_config
        expect(config.blocks[:on_stream_error]).not_to be_nil
      end
    end

    context "error handling" do
      it "raises error for invalid stream_size" do
        expect {
          agent_class.class_eval do
            intelligent_streaming stream_size: 0, over: :companies
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "raises error for non-integer stream_size" do
        expect {
          agent_class.class_eval do
            intelligent_streaming stream_size: "100", over: :companies
          end
        }.to raise_error(ArgumentError, /stream_size must be a positive integer/)
      end

      it "prevents calling intelligent_streaming twice" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies
        end

        expect {
          agent_class.class_eval do
            intelligent_streaming stream_size: 200, over: :items
          end
        }.to raise_error(RAAF::DSL::IntelligentStreaming::ConfigurationError, /already configured/)
      end

      it "allows override with explicit flag" do
        agent_class.class_eval do
          intelligent_streaming stream_size: 100, over: :companies
        end

        agent_class.class_eval do
          intelligent_streaming stream_size: 200, over: :items, override: true
        end

        config = agent_class.streaming_config
        expect(config.stream_size).to eq(200)
        expect(config.array_field).to eq(:items)
      end
    end
  end

  describe ".streaming_trigger?" do
    it "returns false when not configured" do
      expect(agent_class.streaming_trigger?).to be(false)
    end

    it "returns true when configured" do
      agent_class.class_eval do
        intelligent_streaming stream_size: 100, over: :companies
      end

      expect(agent_class.streaming_trigger?).to be(true)
    end
  end

  describe ".streaming_config?" do
    it "returns false when not configured" do
      expect(agent_class.streaming_config?).to be(false)
    end

    it "returns true when configured" do
      agent_class.class_eval do
        intelligent_streaming stream_size: 100, over: :companies
      end

      expect(agent_class.streaming_config?).to be(true)
    end
  end

  describe ".streaming_config" do
    it "returns nil when not configured" do
      expect(agent_class.streaming_config).to be_nil
    end

    it "returns the configuration when configured" do
      agent_class.class_eval do
        intelligent_streaming stream_size: 100, over: :companies
      end

      config = agent_class.streaming_config
      expect(config).to be_a(RAAF::DSL::IntelligentStreaming::Config)
      expect(config.stream_size).to eq(100)
    end
  end

  describe ".with_streaming_in" do
    let(:streaming_agent) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "StreamingAgent"
        intelligent_streaming stream_size: 100, over: :items
      end
    end

    let(:normal_agent) do
      Class.new(RAAF::DSL::Agent) do
        agent_name "NormalAgent"
      end
    end

    it "finds agents with streaming configuration" do
      agents = [normal_agent, streaming_agent, normal_agent]
      result = RAAF::DSL::Agent.with_streaming_in(agents)

      expect(result).to eq([streaming_agent])
    end

    it "returns empty array when no streaming agents" do
      agents = [normal_agent, normal_agent]
      result = RAAF::DSL::Agent.with_streaming_in(agents)

      expect(result).to eq([])
    end

    it "finds multiple streaming agents" do
      another_streaming = Class.new(RAAF::DSL::Agent) do
        agent_name "AnotherStreaming"
        intelligent_streaming stream_size: 50, over: :data
      end

      agents = [streaming_agent, normal_agent, another_streaming]
      result = RAAF::DSL::Agent.with_streaming_in(agents)

      expect(result).to eq([streaming_agent, another_streaming])
    end
  end

  describe "thread safety" do
    it "uses thread-safe storage for configuration" do
      agent_class.class_eval do
        intelligent_streaming stream_size: 100, over: :companies
      end

      # Simulate access from multiple threads
      results = []
      threads = 10.times.map do
        Thread.new do
          config = agent_class.streaming_config
          results << config.stream_size
        end
      end

      threads.each(&:join)

      expect(results).to all(eq(100))
      expect(results.size).to eq(10)
    end
  end

  describe "inheritance" do
    it "does not inherit streaming configuration from parent by default" do
      agent_class.class_eval do
        intelligent_streaming stream_size: 100, over: :companies
      end

      child_class = Class.new(agent_class) do
        agent_name "ChildAgent"
      end

      # Child classes don't inherit class instance variables
      expect(child_class.streaming_trigger?).to be(false)
      expect(child_class.streaming_config).to be_nil
    end

    it "allows child to define its own configuration" do
      agent_class.class_eval do
        intelligent_streaming stream_size: 100, over: :companies
      end

      child_class = Class.new(agent_class) do
        agent_name "ChildAgent"
        intelligent_streaming stream_size: 200, over: :items
      end

      expect(child_class.streaming_config.stream_size).to eq(200)
      expect(child_class.streaming_config.array_field).to eq(:items)

      # Parent configuration unchanged
      expect(agent_class.streaming_config.stream_size).to eq(100)
    end
  end
end