# frozen_string_literal: true

require_relative "../context_access"

module RAAF
  module DSL
    module Prompts
      # Base class for AI prompts with Phlex-inspired design and automatic context access
      #
      # This class provides a clean, convention-over-configuration way to build AI prompts 
      # using heredocs for natural text writing with Ruby interpolation support. Context 
      # variables are automatically accessible via method_missing without requiring 
      # explicit declarations.
      #
      # Key features:
      # - Phlex-inspired API for building prompts
      # - Automatic context variable access via method_missing
      # - Clean Ruby error messages when variables are missing
      # - Support for context_variables from agents
      # - Direct context access from initialization
      #
      # @abstract Subclasses must implement {#system} and {#user} methods
      #
      # @example Basic prompt with automatic context access
      #   class CompanyEnrichment < RAAF::DSL::Prompts::Base
      #     def system
      #       <<~SYSTEM
      #         You are an AI assistant specializing in company data enrichment.
      #
      #         Your role is to research #{company.name} and fill in these attributes:
      #         #{attributes.map { |a| "- #{a}" }.join("\n")}
      #       SYSTEM
      #     end
      #
      #     def user
      #       <<~USER
      #         Research and enrich data for #{company.name}.
      #         Current website: #{company.website}
      #         Research depth: #{research_depth || 'standard'}
      #       USER
      #     end
      #   end
      #
      # @example Context variables from agents
      #   class DocumentAnalysis < RAAF::DSL::Prompts::Base
      #     def system
      #       <<~SYSTEM
      #         You are a document analysis specialist.
      #         Document: #{document_name}
      #         Analysis type: #{analysis_type || 'standard'}
      #       SYSTEM
      #     end
      #
      #     def user
      #       "Please analyze the document using #{analysis_type || 'standard'} analysis."
      #     end
      #   end
      #
      # @example Usage with agents
      #   # In agent DSL configuration
      #   class MyAgent < RAAF::DSL::Agents::Base
      #     include RAAF::DSL::AgentDsl
      #
      #     agent_name "DocumentProcessor"
      #     prompt_class DocumentAnalysis
      #   end
      #
      # @see RAAF::DSL::AgentDsl For integration with agents
      # @since 0.1.0
      #
      class Base
        include RAAF::Logger
        include RAAF::DSL::ContextAccess

        # Inheritance callback for setup
        #
        # @param subclass [Class] The inheriting subclass
        # @api private
        #
        def self.inherited(subclass)
          super
        end


        # Schema functionality has been moved to agent classes
        # Prompts now focus purely on content generation


        def initialize(**kwargs)
          @context = kwargs
          @context_variables = kwargs[:context_variables] if kwargs[:context_variables]
        end

        # Access to the stored context
        attr_reader :context
        attr_reader :context_variables

        # System prompt - override in subclasses
        def system
          raise NotImplementedError, "Subclasses must implement #system"
        end

        # User prompt - override in subclasses
        def user
          raise NotImplementedError, "Subclasses must implement #user"
        end


        # Render both prompts as a hash (for compatibility with PromptLoader)
        def render_messages
          {
            system: render(:system),
            user: render(:user)
          }
        end

        # Render a specific prompt type
        def render(type = nil)
          if type
            render_prompt(type)
          else
            # Default to rendering both as a hash
            render_messages
          end
        end

        protected

        # Render a specific prompt method
        def render_prompt(type)
          begin
            # Call the method and get its return value
            content = send(type)

            # If it's an array (multiple heredocs), join them
            if content.is_a?(Array)
              content.map(&:to_s).map(&:rstrip).join("\n\n")
            else
              content.to_s.rstrip
            end
          rescue StandardError => e
            # Re-raise with additional context but preserve the original error and stack trace
            raise e.class, "Error in #{type} method of #{self.class.name}: #{e.message}", e.backtrace
          end
        end

        # Context access now handled by RAAF::DSL::ContextAccess module
      end
    end
  end
end
