# frozen_string_literal: true

require "raaf-core"
require_relative "raaf/tools/basic/version"
require_relative "raaf/tools/basic/calculator"
require_relative "raaf/tools/basic/weather"

##
# RAAF Tools Basic - Essential tools and utilities for AI agents
#
# This gem provides basic tools that extend AI agent capabilities with common
# utility functions including safe mathematical calculations and mock weather data.
#
# == Available Tools
#
# * **Calculator** - Safe mathematical calculations (from basic_example.rb)
# * **Weather** - Mock weather data (from basic_example.rb)
#
# == Usage
#
#   require 'raaf-tools-basic'
#
#   # Create an agent with basic tools
#   agent = RubyAIAgentsFactory::Agent.new(
#     name: "Assistant",
#     instructions: "You are a helpful assistant with basic tools",
#     model: "gpt-4o"
#   )
#
#   # Add basic tools
#   agent.add_tool(RubyAIAgentsFactory::Tools::Basic.calculator)
#   agent.add_tool(RubyAIAgentsFactory::Tools::Basic.weather)
#
# == Bulk Tool Addition
#
#   # Add all basic tools at once
#   RubyAIAgentsFactory::Tools::Basic.add_all_tools(agent)
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RubyAIAgentsFactory
  module Tools
    module Basic
      class << self
        ##
        # Add all basic tools to an agent
        #
        # @param agent [RubyAIAgentsFactory::Agent] Target agent
        # @return [void]
        #
        def add_all_tools(agent)
          agent.add_tool(calculator)
          agent.add_tool(weather)
        end

        ##
        # Calculator tool
        #
        # @return [RubyAIAgentsFactory::FunctionTool] Calculator tool
        #
        def calculator
          Calculator.tool
        end

        ##
        # Weather tool
        #
        # @return [RubyAIAgentsFactory::FunctionTool] Weather tool
        #
        def weather
          Weather.tool
        end
      end
    end
  end
end