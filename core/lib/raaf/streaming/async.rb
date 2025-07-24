# frozen_string_literal: true

require_relative "base"
require_relative "async_agent"
require_relative "async_runner"
require_relative "providers/responses_provider"
require_relative "../models/responses_provider"

module RAAF

  ##
  # Async module provides true async/await support for RAAF
  #
  # This module implements async/await patterns that match Python's async-first
  # design, enabling non-blocking I/O operations and concurrent execution
  # of agent workflows. Built on Ruby's Async gem for high-performance
  # concurrent processing.
  #
  # @example Basic async agent usage
  #   require 'raaf-core'
  #
  #   # Create async agent
  #   agent = RAAF::Async.agent(
  #     name: "Assistant",
  #     instructions: "You are a helpful assistant.",
  #     model: "gpt-4o"
  #   )
  #
  #   # Run asynchronously
  #   Async do
  #     result = RAAF::Async.run(agent, "Hello world").wait
  #     puts result.messages.last[:content]
  #   end
  #
  # @example Concurrent agent execution
  #   Async do
  #     # Run multiple agents concurrently
  #     tasks = [
  #       Async { RAAF::Async.run(agent1, "Task 1") },
  #       Async { RAAF::Async.run(agent2, "Task 2") },
  #       Async { RAAF::Async.run(agent3, "Task 3") }
  #     ]
  #
  #     results = tasks.map(&:wait)
  #     results.each { |result| puts result.messages.last[:content] }
  #   end
  #
  # @example Async tools with I/O operations
  #   agent.add_tool(->(url:) {
  #     # Async HTTP request
  #     Async::HTTP::Internet.new.get(url).read
  #   })
  #
  #   # Tool calls will run asynchronously without blocking
  #   Async do
  #     result = agent.run_async("Fetch data from https://api.example.com")
  #     puts result.wait.messages.last[:content]
  #   end
  #
  # @see https://github.com/socketry/async Ruby Async gem
  # @since 1.0.0
  #
  module Async

    ##
    # Create an async agent
    #
    # Creates an agent instance configured for asynchronous execution.
    # The agent supports concurrent tool calls and non-blocking I/O.
    #
    # @param kwargs [Hash] Agent configuration options
    # @option kwargs [String] :name Agent name
    # @option kwargs [String] :instructions System prompt for the agent
    # @option kwargs [String] :model OpenAI model to use
    # @option kwargs [Array<Tool>] :tools Initial tools for the agent
    # @return [Async::Agent] Configured async agent
    #
    # @example
    #   agent = RAAF::Async.agent(
    #     name: "DataProcessor",
    #     instructions: "Process data efficiently",
    #     model: "gpt-4o"
    #   )
    #
    def self.agent(**)
      Agent.new(**)
    end

    ##
    # Create an async runner
    #
    # Creates a runner instance for executing agent conversations
    # asynchronously with support for concurrent operations.
    #
    # @param agent [Async::Agent] The agent to run
    # @param kwargs [Hash] Runner configuration options
    # @return [Async::Runner] Configured async runner
    #
    # @example
    #   runner = RAAF::Async.runner(
    #     agent: agent,
    #     max_turns: 5,
    #     timeout: 30
    #   )
    #
    def self.runner(agent:, **)
      Runner.new(agent: agent, **)
    end

    ##
    # Run an agent asynchronously
    #
    # Executes an agent conversation asynchronously, returning a task
    # that can be awaited or run concurrently with other operations.
    #
    # @param agent [Async::Agent] The agent to run
    # @param messages [String, Array<Hash>] Initial message(s) or conversation
    # @param kwargs [Hash] Additional run configuration
    # @return [Async::Task] Task that resolves to conversation result
    #
    # @example Single message
    #   task = RAAF::Async.run(agent, "Hello")
    #   result = task.wait  # Blocks until completion
    #
    # @example With configuration
    #   task = RAAF::Async.run(
    #     agent,
    #     "Complex query",
    #     max_turns: 3,
    #     temperature: 0.7
    #   )
    #
    def self.run(agent, messages, **)
      runner = Runner.new(agent: agent)
      runner.run_async(messages, **)
    end

    # Example usage:
    #
    # require 'raaf-core'
    #
    # # Create async agent
    # agent = RAAF::Async.agent(
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
    #   result = RAAF::Async.run(agent, "Search for Ruby async patterns").wait
    #   puts result.messages.last[:content]
    # end

  end

end
