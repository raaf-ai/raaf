# frozen_string_literal: true

require "raaf-core"
require_relative "raaf/misc/version"

# Load all misc components
require_relative "raaf/misc/voice/voice_workflow"
require_relative "raaf/misc/prompts/prompts"
require_relative "raaf/misc/extensions/extensions"
require_relative "raaf/misc/data_pipeline/data_pipeline"
require_relative "raaf/misc/multimodal/multi_modal"

##
# RAAF Misc - Miscellaneous utilities for Ruby AI Agents Factory
#
# This gem provides miscellaneous utilities and components for the Ruby AI Agents Factory (RAAF)
# ecosystem. It consolidates several smaller components into a single gem for easier management:
#
# == Components
#
# * **Voice Workflows** - Voice interaction and speech processing capabilities
# * **Prompt Management** - Prompt utilities and management tools
# * **Extensions** - Plugin architecture and extension points
# * **Data Pipeline** - Data processing and transformation utilities  
# * **Multimodal** - Multi-modal content processing (text, images, audio)
#
# == Usage
#
#   require 'raaf-misc'
#
#   # Voice workflow
#   voice = RubyAIAgentsFactory::Misc::Voice::VoiceWorkflow.new
#
#   # Prompt management
#   prompts = RubyAIAgentsFactory::Misc::Prompts::Manager.new
#
#   # Extensions
#   extensions = RubyAIAgentsFactory::Misc::Extensions::Manager.new
#
#   # Data pipeline
#   pipeline = RubyAIAgentsFactory::Misc::DataPipeline::Processor.new
#
#   # Multimodal processing
#   multimodal = RubyAIAgentsFactory::Misc::Multimodal::Processor.new
#
# @author Ruby AI Agents Factory Team
# @since 1.0.0
module RubyAIAgentsFactory
  module Misc
    # Misc gem version
    VERSION = "0.1.0"
  end
end