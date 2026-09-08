# frozen_string_literal: true

require "spec_helper"
require "raaf/dsl/pipeline_dsl"
require "timeout"

RSpec.describe RAAF::DSL::PipelineDSL::ConfiguredAgent do
  let(:base_agent) do
    Class.new(RAAF::DSL::Agent) do
      agent_name "BaseAgent"

      context do
        required :input
        output :output
      end

      def run
        { output: "processed", limit_used: @context[:limit] }
      end
    end
  end

  describe "#initialize" do
    it "wraps agent class with configuration options" do
      configured = described_class.new(base_agent, timeout: 60, retry: 3)
      expect(configured.agent_class).to eq(base_agent)
      expect(configured.options).to eq({ timeout: 60, retry: 3 })
    end
  end

  describe "configuration methods" do
    let(:configured) { described_class.new(base_agent, {}) }

    # WrapperDSL's configuration methods are non-destructive: each returns a new
    # wrapper carrying the merged options and leaves the receiver alone.
    it "returns a new wrapper from timeout configuration" do
      result = configured.timeout(30)

      expect(result).not_to be(configured)
      expect(result).to be_a(described_class)
      expect(result.options[:timeout]).to eq(30)
      expect(configured.options).to eq({})
    end

    it "returns a new wrapper from retry configuration" do
      result = configured.retry(5)

      expect(result).not_to be(configured)
      expect(result.options[:retry]).to eq(5)
      expect(configured.options).to eq({})
    end

    it "returns a new wrapper from limit configuration" do
      result = configured.limit(100)

      expect(result).not_to be(configured)
      expect(result.options[:limit]).to eq(100)
      expect(configured.options).to eq({})
    end

    it "accumulates options across a chain of configuration calls" do
      result = configured.timeout(30).retry(3).limit(10)

      expect(result.options).to eq({
                                     timeout: 30,
                                     retry: 3,
                                     limit: 10
                                   })
    end

    it "keeps the wrapped agent class through the chain" do
      result = configured.timeout(30).retry(3)

      expect(result.agent_class).to eq(base_agent)
    end

    it "lets a later call override an earlier value" do
      result = configured.timeout(30).timeout(90)

      expect(result.options[:timeout]).to eq(90)
    end
  end

  describe "delegation methods" do
    let(:configured) { described_class.new(base_agent, {}) }

    it "delegates required_fields to wrapped agent" do
      expect(configured.required_fields).to eq([:input])
    end

    it "delegates provided_fields to wrapped agent" do
      expect(configured.provided_fields).to eq([:output])
    end

    it "delegates requirements_met? to wrapped agent" do
      expect(configured.requirements_met?({ input: "test" })).to be true
      expect(configured.requirements_met?({})).to be false
    end

    context "when the wrapped component answers none of them" do
      let(:bare) { described_class.new(Class.new, {}) }

      it "falls back to empty field lists and unconditional readiness" do
        expect(bare.required_fields).to eq([])
        expect(bare.provided_fields).to eq([])
        expect(bare.requirements_met?({})).to be true
      end
    end
  end

  describe "#execute" do
    let(:context) { { input: "test" } }

    it "returns the context the agent ran against" do
      configured = described_class.new(base_agent, {})

      result = configured.execute(context)

      expect(result).to be_a(RAAF::DSL::ContextVariables)
      expect(result[:input]).to eq("test")
    end

    it "merges provided fields back into the context" do
      configured = described_class.new(base_agent, {})

      result = configured.execute(context)

      expect(result[:output]).to eq("processed")
    end

    it "collects the raw agent result for the pipeline's auto-merge" do
      configured = described_class.new(base_agent, {})
      agent_results = []

      configured.execute(context, agent_results)

      expect(agent_results).to eq([{ output: "processed", limit_used: nil }])
    end

    context "with limit" do
      it "passes limit through to the agent context" do
        configured = described_class.new(base_agent, limit: 25)

        result = configured.execute(context)

        expect(result[:limit]).to eq(25)
      end

      it "makes the limit readable by the agent while it runs" do
        configured = described_class.new(base_agent, limit: 25)
        agent_results = []

        configured.execute(context, agent_results)

        expect(agent_results.first[:limit_used]).to eq(25)
      end
    end

    # timeout and retry are deliberately NOT enforced by this wrapper. It hands
    # them to the agent's own retry/timeout machinery so that retry_on, circuit
    # breakers and backoff configured on the agent stay in charge.
    context "with control options" do
      it "keeps timeout and retry out of the agent context" do
        configured = described_class.new(base_agent, timeout: 30, retry: 3)

        result = configured.execute(context)

        expect(result[:timeout]).to be_nil
        expect(result[:retry]).to be_nil
      end

      it "does not cut an agent short that outlives the timeout" do
        slow_agent = Class.new(RAAF::DSL::Agent) do
          agent_name "SlowAgent"

          def run
            sleep(0.05)
            { output: "done" }
          end
        end

        configured = described_class.new(slow_agent, timeout: 0.001)

        expect { configured.execute(context) }.not_to raise_error
      end

      it "lets a failure from the agent propagate rather than retrying it" do
        always_failing = Class.new(RAAF::DSL::Agent) do
          agent_name "AlwaysFailing"

          class << self
            attr_accessor :attempt_count
          end

          def run
            self.class.attempt_count += 1
            raise "Permanent error"
          end
        end
        always_failing.attempt_count = 0

        configured = described_class.new(always_failing, retry: 2)

        expect { configured.execute(context) }.to raise_error("Permanent error")
        expect(always_failing.attempt_count).to eq(1)
      end
    end
  end

  describe "chainability" do
    let(:configured) { described_class.new(base_agent, timeout: 30) }
    let(:other_agent) { Class.new(RAAF::DSL::Agent) }

    it "maintains chainability with >> operator" do
      result = configured >> other_agent
      expect(result).to be_a(RAAF::DSL::PipelineDSL::ChainedAgent)
    end

    it "maintains parallel support with | operator" do
      result = configured | other_agent
      expect(result).to be_a(RAAF::DSL::PipelineDSL::ParallelAgents)
    end
  end
end
