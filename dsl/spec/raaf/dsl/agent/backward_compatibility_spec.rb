# frozen_string_literal: true

require "spec_helper"

RSpec.describe RAAF::DSL::Agent, "backward compatibility" do
  describe "Backward Compatibility" do
    it "works with old initialization style" do
      agent = TestAgents::BasicTestAgent.new(
        context_variables: RAAF::DSL::ContextVariables.new(foo: "bar"),
        processing_params: { baz: "qux" }
      )
      # The context_variables parameter gets stored under "context_variables" key
      expect(agent.context.to_h["context_variables"].to_h).to include("foo" => "bar")
      expect(agent.processing_params).to eq({ baz: "qux" })
    end

    it "supports run method" do
      agent = TestAgents::BasicTestAgent.new(context: RAAF::DSL::ContextVariables.new)
      expect(agent).to respond_to(:run)
      # Note: call method not implemented in current version
    end
  end
end