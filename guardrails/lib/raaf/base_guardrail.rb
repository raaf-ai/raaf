# frozen_string_literal: true

require_relative "base"

module RubyAIAgentsFactory
  module Guardrails
    # Base class for guardrails that provides common functionality
    class BaseGuardrail < Base
      def initialize(**options)
        super(**options)
      end
    end
  end
end