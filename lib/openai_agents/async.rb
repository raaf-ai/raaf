# frozen_string_literal: true

require_relative "async/base"
require_relative "async/agent"
require_relative "async/runner"
require_relative "async/providers/responses_provider"

module OpenAIAgents
  # Async module provides true async/await support for OpenAI Agents
  # matching Python's async-first design
  module Async
    # Create an async agent
    def self.agent(**)
      Agent.new(**)
    end

    # Create an async runner
    def self.runner(agent:, **)
      Runner.new(agent: agent, **)
    end

    # Run an agent asynchronously
    def self.run(agent, messages, **)
      runner = Runner.new(agent: agent)
      runner.run_async(messages, **)
    end

    # Example usage:
    #
    # require 'openai_agents/async'
    #
    # # Create async agent
    # agent = OpenAIAgents::Async.agent(
    #   name: "Assistant",
    #   instructions: "You are a helpful assistant.",
    #   model: "gpt-4o"
    # )
    #
    # # Add async tool
    # agent.add_tool(-> (query:) {
    #   # This will run asynchronously
    #   sleep 1  # Simulating API call
    #   "Search results for: #{query}"
    # })
    #
    # # Run asynchronously
    # Async do
    #   result = OpenAIAgents::Async.run(agent, "Search for Ruby async patterns").wait
    #   puts result.messages.last[:content]
    # end
  end
end
