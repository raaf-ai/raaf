# frozen_string_literal: true

require_relative "rspec/prompt_matchers"
require_relative "rspec/agent_matchers"

# RSpec integration for AI Agent DSL
#
# This module provides RSpec matchers and helpers for testing AI Agent DSL components.
# It includes custom matchers for prompt testing, validation, and context handling.
#
# @example Basic setup
#   # In your spec_helper.rb or rails_helper.rb
#   require 'ai_agent_dsl/rspec'
#
# @example Usage in tests
#   RSpec.describe MyPrompt do
#     it "includes expected content" do
#       expect(MyPrompt).to include_prompt_content("analysis")
#         .with_context(document: "test.pdf")
#     end
#   end
#
# @since 0.1.0
module RAAF

  module DSL

    module RSpec

      # Configure RSpec to include our custom matchers
      #
      # This method is automatically called when the module is loaded if RSpec is available.
      # It includes all the custom matchers in the RSpec configuration.
      #
      # @return [void]
      def self.configure_rspec!
        return unless defined?(::RSpec)

        ::RSpec.configure do |config|
          config.include PromptMatchers
          config.include AgentMatchers
        end
      end

      # Manually include matchers in a specific context
      #
      # Use this if you want to include matchers in a specific test file or context
      # rather than globally.
      #
      # @example
      #   RSpec.describe MyPrompt do
      #     include RAAF::DSL::RSpec::PromptMatchers
      #
      #     it "tests prompt content" do
      #       expect(MyPrompt).to include_prompt_content("test")
      #     end
      #   end
      #
      # @param context [Object] The context to include matchers in
      # @return [void]
      def self.include_matchers_in(context)
        context.include PromptMatchers
        context.include AgentMatchers
      end

    end

  end

end

# Auto-configure RSpec if it's available
RAAF::DSL::RSpec.configure_rspec!
