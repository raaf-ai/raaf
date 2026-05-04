# frozen_string_literal: true

require 'spec_helper'
require 'active_support/all'
require 'raaf/dsl/service'
require 'raaf/dsl/pipelineable'
require 'raaf/dsl/pipeline_dsl/remapped_agent'
require 'raaf/dsl/pipeline_dsl/configured_agent'
require 'raaf/dsl/pipeline_dsl/parallel_agents'

# Regression coverage for the Service-vs-Agent dispatch bug in pipeline wrappers.
#
# RAAF::DSL::Service implementations expose `call` (not `run`). Several pipeline
# wrappers historically hardcoded `agent.run`, which crashes for Services in two
# overlapping ways:
#
#   1. Services don't define `run`, so the call falls into ContextAccess#method_missing.
#   2. Services with a restricted `context do` block then raise
#      RAAF::DSL::ContextAccessError, claiming `run` is an undeclared context variable.
#
# These specs lock in the correct dispatch (Service -> call, Agent -> run) for every
# wrapper that instantiates and executes the wrapped class.
RSpec.describe 'Pipeline wrapper Service vs Agent dispatch' do
  # Restricted-context Service that mirrors a real production service
  # (e.g. Ai::Services::Company::WebsiteLookup). Only declares :input,
  # so any stray method_missing on an undeclared variable raises
  # ContextAccessError -- which is exactly what we are guarding against.
  let(:restricted_service_class) do
    Class.new(RAAF::DSL::Service) do
      context do
        required :input
        output :output
      end

      def self.name
        'TestRestrictedService'
      end

      def self.required_fields
        [:input]
      end

      def self.provided_fields
        [:output]
      end

      def self.requirements_met?(context)
        context.respond_to?(:has?) ? context.has?(:input) : (context.key?(:input) || context.key?('input'))
      end

      def call
        { success: true, output: "called:#{input}" }
      end
    end
  end

  # A bare Agent stub that exposes `run` (no `call`) so we can also verify
  # the "Agent path" still works after the fix.
  let(:agent_class) do
    Class.new do
      include RAAF::DSL::Pipelineable

      def self.name
        'TestAgent'
      end

      def self.required_fields
        [:input]
      end

      def self.provided_fields
        [:output]
      end

      def self.requirements_met?(context)
        context.key?(:input) || context.key?('input')
      end

      def initialize(**context)
        @context = context
      end

      def run
        { success: true, output: "ran:#{@context[:input]}" }
      end
    end
  end

  let(:context) do
    RAAF::DSL::ContextVariables.new(input: 'value')
  end

  describe RAAF::DSL::PipelineDSL::RemappedAgent do
    it 'invokes #call on a Service (regression: previously hardcoded #run)' do
      wrapper = described_class.new(restricted_service_class, input_mapping: {}, output_mapping: {})

      expect { wrapper.execute(context) }.not_to raise_error
    end

    it 'still invokes #run on an Agent' do
      wrapper = described_class.new(agent_class, input_mapping: {}, output_mapping: {})

      expect { wrapper.execute(context) }.not_to raise_error
    end
  end

  describe RAAF::DSL::PipelineDSL::ConfiguredAgent do
    it 'invokes #call on a Service (regression: previously hardcoded #run)' do
      wrapper = described_class.new(restricted_service_class, {})

      expect { wrapper.execute(context) }.not_to raise_error
    end

    it 'still invokes #run on an Agent' do
      wrapper = described_class.new(agent_class, {})

      expect { wrapper.execute(context) }.not_to raise_error
    end
  end

  describe RAAF::DSL::PipelineDSL::ParallelAgents do
    it 'invokes #call on a Service in a parallel branch (regression: previously hardcoded #run)' do
      wrapper = described_class.new([restricted_service_class])

      expect { wrapper.execute(context) }.not_to raise_error
    end

    it 'still invokes #run on an Agent in a parallel branch' do
      wrapper = described_class.new([agent_class])

      expect { wrapper.execute(context) }.not_to raise_error
    end
  end
end
