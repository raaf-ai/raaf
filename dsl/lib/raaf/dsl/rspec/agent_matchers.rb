# frozen_string_literal: true

# Custom RSpec matchers for AI Agent DSL agent testing
#
# This module provides matchers for testing agent behaviors, handoffs, and responses.
# It includes matchers for validating agent orchestration and workflow patterns.
#
# @example Basic usage
#   RSpec.describe MyAgent do
#     it "hands off to the correct agent" do
#       result = agent.process(input)
#       expect(result).to handoff_to("Ai::Agents::Company::Enrichment")
#     end
#   end
#
# @since 0.1.0
module RAAF

  module DSL

    module RSpec

      module AgentMatchers

        # Matcher for testing agent handoff behavior
        #
        # Tests whether an agent result contains a handoff to a specific agent.
        # Works with both string and symbol keys for the handoff_to field.
        #
        # @param expected_agent [String] The expected agent class name to handoff to
        # @return [RSpec::Matchers::BuiltIn::BaseMatcher] The matcher instance
        #
        # @example Testing agent handoff
        #   expect(agent_result).to handoff_to("Ai::Agents::Company::Enrichment")
        #
        # @example With hash result
        #   result = { "handoff_to" => "Ai::Agents::Company::Enrichment" }
        #   expect(result).to handoff_to("Ai::Agents::Company::Enrichment")
        #
        # @example With symbol keys
        #   result = { handoff_to: "Ai::Agents::Company::Enrichment" }
        #   expect(result).to handoff_to("Ai::Agents::Company::Enrichment")
        #
        # @since 0.1.0
        def handoff_to(expected_agent)
          HandoffToMatcher.new(expected_agent)
        end

        # Custom matcher class for handoff_to testing
        class HandoffToMatcher

          def initialize(expected_agent)
            @expected_agent = expected_agent
          end

          def matches?(actual)
            @actual = actual
            @actual_handoff = actual["handoff_to"] || actual[:handoff_to]
            @actual_handoff == @expected_agent
          end

          def failure_message
            "expected #{@actual.inspect} to handoff to #{@expected_agent.inspect}, but got #{@actual_handoff.inspect}"
          end

          def failure_message_when_negated
            "expected #{@actual.inspect} not to handoff to #{@expected_agent.inspect}, but it did"
          end

          def description
            "handoff to #{@expected_agent.inspect}"
          end

        end

      end

    end

  end

end
